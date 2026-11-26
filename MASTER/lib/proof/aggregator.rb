# frozen_string_literal: true

module Master
  class Proof
    # Rolls per-mode proof rows into one verdict under data/core_spine.yml's
    # proof_policy. Pure: no I/O, no state. A row is
    # { mode:, status: :pass|:fail|:inconclusive|:skipped, required:, evidence_ok: }
    # with string or symbol keys and values. INCONCLUSIVE is never PASS.
    module Aggregator
      POLICIES = %i[strict_list opt_in].freeze

      module_function

      def aggregate(results, policy: :strict_list)
        raise ArgumentError, "unknown proof policy: #{policy}" unless POLICIES.include?(policy)
        return :inapplicable if results.nil?

        rows = Array(results).map { |row| normalize(row) }
        return :inconclusive if rows.empty?
        return :fail if rows.any? { |row| row[:status] == :fail }

        required = required_rows(rows, policy)
        return :inconclusive if required.empty?

        required.all? { |row| row[:status] == :pass } ? :pass : :inconclusive
      end

      def aggregate_subjects(statuses)
        values = Array(statuses).map { |status| status.to_s.to_sym }
        return :inapplicable if values.empty?
        return :fail if values.include?(:fail)
        return :inconclusive if values.include?(:inconclusive)

        values.all? { |status| %i[pass inapplicable].include?(status) } ? :pass : :inconclusive
      end

      # A pass or fail whose evidence is not the right class proves nothing.
      def normalize(row)
        value = ->(key) { row.fetch(key) { row[key.to_s] } }
        status = value.call(:status).to_s.to_sym
        demoted = %i[pass fail].include?(status) && value.call(:evidence_ok) == false
        { mode: value.call(:mode), status: demoted ? :inconclusive : status, required: value.call(:required) }
      end

      # strict_list: every row unless marked optional (all rows when that leaves
      # none); opt_in: only rows marked required, so none required proves nothing.
      def required_rows(rows, policy)
        return rows.select { |row| row[:required] == true } if policy == :opt_in

        listed = rows.reject { |row| row[:required] == false }
        listed.empty? ? rows : listed
      end
    end
  end
end
