# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "securerandom"
require "time"

module Master
  module Trace
    # CausalTrace — the evidence class for agent, council and /fix behaviour.
    #
    # A claim about what an agent or council did is unverified without a
    # replayable causal trace (TRUTHFUL_STATUS_causal_trace_is_evidence).
    # This module defines the shape, validates it, and appends to an
    # append-only JSONL ledger under .master/traces/.
    #
    # It does not execute tools or call models; it records what already ran.
    module CausalTrace
      SCHEMA = 1
      LEDGER_DIR = File.join(".master", "traces")
      LEDGER_FILE = "causal.jsonl"

      REQUIRED = %w[schema_version trace_id run_id started_at steps].freeze
      STEP_KINDS = %w[model_turn tool_call tool_result decision outcome context].freeze
      CONTEXT_KEY = :master_causal_trace_context
      SENSITIVE_KEY = /prompt|message|content|response|candidate|secret|password|authorization|api[_-]?key|credential|raw|source_code|query|body/i
      MAX_METADATA_DEPTH = 3

      module_function

      # One run owns one causal trace. Nested operations restore their caller's
      # context; ordinary chat turns outside /fix do not create persistent traces.
      def start(run_id:, root: nil, agent: "master")
        context = {
          run_id: run_id.to_s,
          root: File.expand_path(root || (defined?(Master::REPO_ROOT) && Master::REPO_ROOT) || Dir.pwd),
          agent: agent.to_s,
          started_at: Time.now.utc,
          steps: [],
          profile_start: profile_snapshot,
          previous: Thread.current[CONTEXT_KEY],
        }
        raise ArgumentError, "run_id required" if context[:run_id].empty?

        Thread.current[CONTEXT_KEY] = context
        context
      end

      def current
        Thread.current[CONTEXT_KEY]
      end

      # Inputs and outputs are deliberately metadata-only. Prompt, source,
      # candidate and provider response bodies never enter the durable ledger.
      def step(kind:, name:, input: {}, output: {})
        context = current
        return unless context

        context[:steps] << {
          "kind" => kind.to_s,
          "name" => name.to_s,
          "input" => safe_metadata(input),
          "output" => safe_metadata(output),
        }
        context[:steps].length
      rescue StandardError
        nil
      end

      def finish(context, outcome:, metadata: {})
        return unless context

        context[:steps] << {
          "kind" => "outcome",
          "name" => "run.terminal",
          "output" => safe_metadata(outcome),
        }
        runtime_profile = profile_delta(context[:profile_start], profile_snapshot)
        trace_metadata = metadata.is_a?(Hash) ? metadata.dup : {}
        trace_metadata[:runtime_profile] = runtime_profile if runtime_profile
        trace = build(
          run_id: context.fetch(:run_id),
          agent: context.fetch(:agent),
          started_at: context.fetch(:started_at),
          finished_at: Time.now.utc,
          steps: context.fetch(:steps),
          metadata: trace_metadata,
        )
        record(trace, root: context.fetch(:root))
      ensure
        clear(context)
      end

      def clear(context)
        return unless context
        return unless Thread.current[CONTEXT_KEY].equal?(context)

        Thread.current[CONTEXT_KEY] = context[:previous]
      end

      # Portable profiling from Ruby process and GC counters. This measures
      # local execution only; it is not provider billing, resident memory or eBPF.
      def profile_snapshot
        times = Process.times
        gc = GC.stat
        {
          monotonic: Process.clock_gettime(Process::CLOCK_MONOTONIC),
          user_cpu: times.utime,
          system_cpu: times.stime,
          allocated_objects: gc[:total_allocated_objects],
          heap_allocated_pages: gc[:heap_allocated_pages],
          minor_gc_count: gc[:minor_gc_count],
          major_gc_count: gc[:major_gc_count],
        }
      rescue StandardError
        nil
      end

      def profile_delta(before, after)
        return unless before.is_a?(Hash) && after.is_a?(Hash)

        {
          source: "ruby_process_and_gc_counters",
          measured: true,
          wall_ms: ((after[:monotonic] - before[:monotonic]) * 1_000).round(2),
          cpu_ms: (((after[:user_cpu] - before[:user_cpu]) +
                    (after[:system_cpu] - before[:system_cpu])) * 1_000).round(2),
          allocated_objects: after[:allocated_objects].to_i - before[:allocated_objects].to_i,
          heap_allocated_pages_delta: after[:heap_allocated_pages].to_i - before[:heap_allocated_pages].to_i,
          minor_gc_count: after[:minor_gc_count].to_i - before[:minor_gc_count].to_i,
          major_gc_count: after[:major_gc_count].to_i - before[:major_gc_count].to_i,
          provider_usage: "NOT_CAPTURED",
          resident_memory: "NOT_MEASURED",
        }
      rescue StandardError
        nil
      end
      def safe_metadata(value, depth = 0)
        return if depth > MAX_METADATA_DEPTH

        case value
        when Hash
          value.each_with_object({}) do |(key, item), safe|
            name = key.to_s
            next if name.match?(SENSITIVE_KEY)
            clean = safe_metadata(item, depth + 1)
            next if clean.nil?
            safe[name] = clean
            break safe if safe.size >= 24
          end
        when Array
          value.first(16).filter_map { |item| safe_metadata(item, depth + 1) }
        when String
          value.gsub(/\b(?:sk-[A-Za-z0-9_-]{8,}|gh[pousr]_[A-Za-z0-9_]{8,}|github_pat_[A-Za-z0-9_]{8,})\b/, "<redacted>")[0, 256]
        when Symbol
          value.to_s
        when Numeric, TrueClass, FalseClass
          value
        else
          nil
        end
      end

      # Build a validated trace hash. Raises ArgumentError on missing required fields.
      def build(run_id:, steps:, started_at: nil, finished_at: nil, agent: nil, note: nil, metadata: {})
        raise ArgumentError, "run_id required" if run_id.to_s.empty?
        raise ArgumentError, "steps must be a non-empty Array" unless steps.is_a?(Array) && !steps.empty?

        normalised = steps.map.with_index { |step, i| normalise_step(step, i) }
        {
          "schema_version" => SCHEMA,
          "trace_id" => SecureRandom.uuid,
          "run_id" => run_id.to_s,
          "agent" => agent&.to_s,
          "started_at" => (started_at || Time.now.utc).iso8601,
          "finished_at" => finished_at&.iso8601,
          "steps" => normalised,
          "note" => note,
          "metadata" => safe_metadata(metadata).to_h,
        }.compact
      end

      def normalise_step(step, index)
        step = step.transform_keys(&:to_s) if step.is_a?(Hash)
        raise ArgumentError, "step #{index} must be a Hash" unless step.is_a?(Hash)

        kind = step["kind"].to_s
        raise ArgumentError, "step #{index} kind must be one of #{STEP_KINDS.join(", ")}" unless STEP_KINDS.include?(kind)

        {
          "seq" => index + 1,
          "kind" => kind,
          "name" => step["name"]&.to_s,
          "input" => safe_metadata(step["input"]),
          "output" => safe_metadata(step["output"]),
          "at" => step["at"] || Time.now.utc.iso8601,
          "parent_seq" => step["parent_seq"],
          "caused_by" => step["caused_by"],
        }.compact
      end

      # Append a validated trace to the ledger. Returns { path:, sha256:, trace_id: }.
      def record(trace, root: nil)
        root ||= (defined?(Master::REPO_ROOT) && Master::REPO_ROOT) || Dir.pwd
        validate!(trace)
        dir = File.join(root, LEDGER_DIR)
        FileUtils.mkdir_p(dir, mode: 0o700)
        File.chmod(0o700, dir)
        path = File.join(dir, LEDGER_FILE)
        line = JSON.generate(trace)
        File.open(path, "a:UTF-8", 0o600) { |f| f.puts(line) }
        File.chmod(0o600, path)
        {
          path: path,
          sha256: Digest::SHA256.hexdigest(line),
          trace_id: trace["trace_id"],
          runtime_profile: trace.dig("metadata", "runtime_profile"),
        }
      end

      def validate!(trace)
        REQUIRED.each do |key|
          raise ArgumentError, "causal trace missing #{key}" if trace[key].nil? || (trace[key].respond_to?(:empty?) && trace[key].empty?)
        end
        raise ArgumentError, "steps must be non-empty" unless trace["steps"].is_a?(Array) && !trace["steps"].empty?
        true
      end

      # Read recent traces (newest last). For inspection and antigen matching.
      def recent(root: nil, limit: 20)
        root ||= (defined?(Master::REPO_ROOT) && Master::REPO_ROOT) || Dir.pwd
        path = File.join(root, LEDGER_DIR, LEDGER_FILE)
        return [] unless File.file?(path)

        lines = File.readlines(path, encoding: "UTF-8")
        lines.last(limit.to_i).filter_map do |line|
          JSON.parse(line)
        rescue JSON::ParserError
          nil
        end
      end
    end
  end
end
