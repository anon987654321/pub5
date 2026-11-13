# frozen_string_literal: true

require "json"
require_relative "outcome"

module Master
  module Fix
    # Read-only projection of the existing hash-chained coordinator terminal
    # event, repair summaries and LifecycleJournal assessment. It creates no
    # second journal or hash chain: hash and prev_hash are the coordinator
    # ledger's already-verified values.
    class TerminalReceipt
      SCHEMA_VERSION = 1
      REFUSAL_KEYS = %w[
        rejected reflexion_rejected consensus_rejected out_of_scope
        commit_refused validation_failed
      ].freeze

      attr_reader :schema_version, :run_id, :attempt_id, :target,
                  :started_at, :finished_at, :task_contract,
                  :task_contract_digest, :plan_digest, :assessment,
                  :repair_passes, :measured, :changed, :rejected,
                  :inconclusive, :blocked, :resumed, :outcomes,
                  :terminal_state, :result, :category, :ledger_seq,
                  :prev_hash, :hash

      def self.build(start_event:, terminal_event:, repair_events:,
                     journal_run: nil, assessment: nil)
        start_payload = start_event.fetch("payload", {})
        terminal_payload = terminal_event.fetch("payload", {})
        unless start_event["kind"] == "coordinator_started" &&
               terminal_event["kind"] == "coordinator_terminal" &&
               start_event["run_id"] == terminal_event["run_id"]
          raise ArgumentError, "terminal receipt events do not belong to one coordinator run"
        end

        start_attempt = start_payload["attempt_id"].to_s
        terminal_attempt = terminal_payload["attempt_id"].to_s
        unless !start_attempt.empty? && start_attempt == terminal_attempt
          raise ArgumentError, "terminal receipt attempt identity does not match"
        end

        new(
          run_id: terminal_event.fetch("run_id"),
          attempt_id: terminal_attempt,
          target: start_payload["target"],
          started_at: start_event.fetch("at"),
          finished_at: terminal_event.fetch("at"),
          task_contract: start_payload["task_contract"],
          task_contract_digest: start_payload["task_contract_digest"],
          plan_digest: journal_run.is_a?(Hash) ? journal_run.dig("plan", "digest") : nil,
          assessment:,
          repair_events:,
          journal_run:,
          terminal_payload:,
          ledger_seq: terminal_event.fetch("seq"),
          prev_hash: terminal_event.fetch("prev"),
          hash: terminal_event.fetch("hash"),
        )
      end

      def initialize(run_id:, attempt_id:, target:, started_at:, finished_at:,
                     task_contract:, task_contract_digest:, plan_digest:,
                     assessment:, repair_events:, journal_run:,
                     terminal_payload:, ledger_seq:, prev_hash:, hash:)
        @schema_version = SCHEMA_VERSION
        @run_id = run_id.to_s.freeze
        @attempt_id = attempt_id.to_s.freeze
        @target = target&.to_s&.freeze
        @started_at = started_at.to_s.freeze
        @finished_at = finished_at.to_s.freeze
        @task_contract = normalize_contract(task_contract)
        @task_contract_digest = task_contract_digest&.to_s&.freeze
        @plan_digest = plan_digest&.to_s&.freeze
        @assessment = normalize_assessment(assessment)
        @repair_passes = normalize_repairs(repair_events)
        @measured = !@repair_passes.empty? || @assessment["status"] == "verified"
        @changed = @repair_passes.sum { |row| row.fetch("fixed") }
        @rejected = refusal_rows(@repair_passes)
        @inconclusive = inconclusive_reasons(@assessment, @task_contract)
        @terminal_state = terminal_payload.fetch("state", "unknown_outcome").to_s.freeze
        @result = terminal_payload["result"]&.to_s&.freeze
        @category = terminal_payload["category"]&.to_s&.freeze
        @blocked = @terminal_state == "blocked" || @category == "policy"
        @resumed = journal_run.is_a?(Hash) &&
          (journal_run.fetch("resume_count", 0).to_i.positive? ||
           !journal_run["resumed_from"].nil?)
        @outcomes = classify_outcomes.freeze
        @ledger_seq = Integer(ledger_seq)
        @prev_hash = prev_hash.to_s.freeze
        @hash = hash.to_s.freeze
        freeze
      end

      def to_h
        {
          "schema_version" => schema_version,
          "run_id" => run_id,
          "attempt_id" => attempt_id,
          "target" => target,
          "started_at" => started_at,
          "finished_at" => finished_at,
          "task_contract" => task_contract,
          "task_contract_digest" => task_contract_digest,
          "plan_digest" => plan_digest,
          "measured" => measured,
          "assessment" => assessment,
          "changed" => changed,
          "change_coverage" => "per_law_repair_summaries_only",
          "repair_passes" => repair_passes,
          "rejected" => rejected,
          "inconclusive" => inconclusive,
          "blocked" => blocked,
          "resumed" => resumed,
          "outcomes" => outcomes.map(&:to_s),
          "terminal_state" => terminal_state,
          "result" => result,
          "category" => category,
          "ledger_seq" => ledger_seq,
          "prev_hash" => prev_hash,
          "hash" => hash,
        }
      end

      def to_json(*args)
        to_h.to_json(*args)
      end

      # Re-read the entire coordinator chain, then require this exact terminal
      # row to remain present. The receipt's hash is not self-asserted.
      def verify!(log_path:)
        events = Kernel.read_log(log_path)
        event = events.find { |row| row["seq"].to_i == ledger_seq }
        unless event &&
               event["kind"] == "coordinator_terminal" &&
               event["run_id"] == run_id &&
               event.dig("payload", "attempt_id") == attempt_id &&
               event["prev"] == prev_hash &&
               event["hash"] == hash
          raise Kernel::LedgerCorruption, "terminal receipt no longer matches the verified coordinator ledger"
        end

        self
      end

      private

      def normalize_contract(value)
        return {}.freeze unless value.is_a?(Hash)

        keys = %w[schema intent scope preserve proof]
        value.each_with_object({}) do |(key, child), output|
          name = key.to_s
          output[name] = json_copy(child) if keys.include?(name)
        end.then { |item| deep_freeze(item) }
      end

      def normalize_assessment(value)
        source = value.is_a?(Hash) ? value : { "status" => "receipt_missing" }
        keys = %w[status matrix_status matrix_summary surface_coverage blockers]
        normalized = source.each_with_object({}) do |(key, child), output|
          name = key.to_s
          output[name] = json_copy(child) if keys.include?(name)
        end
        normalized["status"] ||= "unavailable"
        deep_freeze(normalized)
      end

      def normalize_repairs(events)
        Array(events).map do |event|
          payload = event["payload"].is_a?(Hash) ? event["payload"] : {}
          breakdown = payload["breakdown"].is_a?(Hash) ? payload["breakdown"] : {}
          {
            "law" => payload["law"].to_s,
            "status" => payload["status"].to_s,
            "fixed" => [Integer(payload.fetch("fixed", 0)), 0].max,
            "breakdown" => breakdown.each_with_object({}) do |(key, count), output|
              number = Integer(count) rescue nil
              output[key.to_s] = number if number && number >= 0
            end.sort.to_h,
          }
        end.then { |rows| deep_freeze(rows) }
      end

      def refusal_rows(rows)
        rows.flat_map do |row|
          row.fetch("breakdown").filter_map do |key, count|
            next unless REFUSAL_KEYS.include?(key) && count.positive?

            { "law" => row.fetch("law"), "reason" => key, "count" => count }
          end
        end.then { |items| deep_freeze(items) }
      end

      def inconclusive_reasons(assessment, contract)
        reasons = []
        reasons << "task_contract:summary_unavailable" if contract.empty?

        unless assessment["status"] == "verified"
          reasons << "assessment:#{assessment["status"]}"
          return deep_freeze(reasons)
        end

        if assessment["matrix_status"].to_s != "complete"
          reasons << "assessment_matrix:#{assessment["matrix_status"] || "unknown"}"
        end
        summary = assessment["matrix_summary"].is_a?(Hash) ? assessment["matrix_summary"] : {}
        pending = summary["pending_cells"].to_i
        uncertain = summary["inconclusive_cells"].to_i
        reasons << "assessment:#{pending}_pending_cells" if pending.positive?
        reasons << "assessment:#{uncertain}_inconclusive_cells" if uncertain.positive?

        surface = assessment["surface_coverage"].is_a?(Hash) ? assessment["surface_coverage"] : {}
        reasons << "surface_coverage:#{surface["status"]}" unless surface["status"] == "complete"
        deep_freeze(reasons)
      end

      def classify_outcomes
        values = []
        values << Outcome::MEASURED if measured
        values << Outcome::CHANGED if changed.positive?
        values << Outcome::REJECTED unless rejected.empty?
        values << Outcome::INCONCLUSIVE unless inconclusive.empty?
        values << Outcome::BLOCKED if blocked
        values << Outcome::RESUMED if resumed
        values
      end

      def json_copy(value)
        JSON.parse(JSON.generate(value))
      end

      def deep_freeze(value)
        case value
        when Hash
          value.each { |key, child| deep_freeze(key); deep_freeze(child) }
        when Array
          value.each { |child| deep_freeze(child) }
        when String
          value.freeze
        end
        value.freeze
      end
    end
  end
end
