# frozen_string_literal: true

module Master
  module Fix
    # Terminal renderings for FourStreamAssessment: the compact summary the
    # terminal event shows, the full per-cell report, and the durable audit
    # record that carries every reading's evidence. This file re-opens the
    # class defined in fix/four_stream_assessment.rb, splitting the reporting
    # responsibility out so each half of the class stays inside the
    # NO_GOD_CLASS budget.
    class FourStreamAssessment
      # Small summary for the terminal event. Full findings remain available via
      # #report; callers need not serialize every unassessed cell to know coverage.
      def summary
        latest = cells.map { |key| [key, history[key].last] }
        {
          laws: laws.size,
          generation:,
          last_mutation_iteration:,
          clean_passes_required: clean_passes,
          expected_cells: cells.size,
          recorded_cells: latest.count { |_key, row| !row.nil? },
          unassessed_cells: latest.count { |_key, row| row.nil? },
          inconclusive_cells: latest.count { |_key, row| row&.status == :inconclusive },
          finding_cells: latest.count { |_key, row| row && FINDING_STATES.include?(row.status) },
          complete: complete?,
          clean: clean?,
          streams: stream_state_counts(latest).transform_keys(&:to_s),
        }
      end

      def report
        latest_by_cell = cells.to_h { |key| [key, history[key].last] }
        {
          laws: laws.size,
          generation: @generation,
          clean_passes_required: clean_passes,
          last_mutation_iteration:,
          streams: STREAMS.map(&:to_s),
          surfaces: surfaces.map(&:to_s),
          expected_cells: cells.size,
          recorded_cells: latest_by_cell.count { |_, row| !row.nil? },
          complete: complete?,
          clean: clean?,
          stream_summary: stream_state_counts(latest_by_cell),
          open_findings: finding_rows(latest_by_cell),
          inconclusive: inconclusive_rows(latest_by_cell),
          unassessed: unassessed_rows(latest_by_cell),
        }
      end

      # Durable per-cell proof, including the complete transition history. The
      # compact terminal summary is intentionally separate from this audit record.
      def evidence_report
        {
          schema_version: 2,
          streams: STREAMS.map(&:to_s),
          surfaces: surfaces.map(&:to_s),
          laws:,
          summary:,
          invalidations: invalidation_rows,
          cells: cell_evidence_rows,
        }
      end

      private

      # Shared state histogram for summary and report: per stream, how many
      # cells sit in each state, with unrecorded cells counting as pending.
      def stream_state_counts(latest)
        STREAMS.to_h do |stream|
          rows = latest.select { |key, _row| key[1] == stream }.map(&:last)
          counts = (STATES + [:pending]).to_h do |state|
            [state, rows.count { |row| row ? row.status == state : state == :pending }]
          end
          [stream, { cells: rows.size, states: counts }]
        end
      end

      def finding_rows(latest_by_cell)
        latest_by_cell.filter_map do |key, row|
          next unless row && (
            %i[violation_found opportunity_found].include?(row.status) ||
            (row.status == :inconclusive && (row.evidence.any? || row.findings.any?))
          )

          { law: key[0], stream: key[1].to_s, surface: key[2].to_s, status: row.status.to_s,
            iteration: row.iteration, reason: row.reason, evidence: row.evidence,
            findings: row.findings }
        end
      end

      def inconclusive_rows(latest_by_cell)
        latest_by_cell.filter_map do |key, row|
          next unless row&.status == :inconclusive

          { law: key[0], stream: key[1].to_s, surface: key[2].to_s,
            iteration: row.iteration, reason: row.reason }
        end
      end

      def unassessed_rows(latest_by_cell)
        latest_by_cell.filter_map do |key, row|
          { law: key[0], stream: key[1].to_s, surface: key[2].to_s } unless row
        end
      end

      def invalidation_rows
        Array(@invalidations).map do |entry|
          {
            iteration: entry[:iteration],
            generation: entry[:generation],
            reason: entry[:reason],
          }
        end
      end

      def cell_evidence_rows
        cells.sort_by { |key| key.map(&:to_s) }.map do |key|
          rows = history[key]
          latest = rows.last
          {
            law: key[0],
            stream: key[1].to_s,
            surface: key[2].to_s,
            status: latest ? latest.status.to_s : "pending",
            clean_streak: clean_streak(key),
            readings: rows.map { |row| reading_evidence(row) },
          }
        end
      end

      def reading_evidence(row)
        {
          iteration: row.iteration,
          generation: row.generation,
          status: row.status.to_s,
          reason: row.reason,
          evidence: json_safe_value(row.evidence),
          findings: json_safe_value(row.findings),
          repair: repair_evidence(row.repair),
        }
      end

      def repair_evidence(repair)
        return if repair.nil?

        if repair.is_a?(Hash)
          {
            changed: repair[:changed] == true || repair["changed"] == true,
            retryable: repair[:retryable] == true || repair["retryable"] == true,
            reason: (repair[:reason] || repair["reason"]).to_s[0, 240],
          }
        else
          { changed: repair == true }
        end
      end

      def json_safe_value(value)
        case value
        when NilClass, TrueClass, FalseClass, Numeric, String
          value
        when Symbol
          value.to_s
        when Array
          value.map { |entry| json_safe_value(entry) }
        when Hash
          value.each_with_object({}) do |(key, entry), normalized|
            normalized[key.to_s] = json_safe_value(entry)
          end
        else
          value.respond_to?(:to_h) ? json_safe_value(value.to_h) : value.to_s
        end
      end
    end
  end
end
