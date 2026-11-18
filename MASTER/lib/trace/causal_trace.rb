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

      module_function

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
          "metadata" => metadata.is_a?(Hash) ? metadata : {},
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
          "input" => step["input"],
          "output" => step["output"],
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
        FileUtils.mkdir_p(dir)
        path = File.join(dir, LEDGER_FILE)
        line = JSON.generate(trace)
        File.open(path, "a:UTF-8") { |f| f.puts(line) }
        {
          path: path,
          sha256: Digest::SHA256.hexdigest(line),
          trace_id: trace["trace_id"],
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
