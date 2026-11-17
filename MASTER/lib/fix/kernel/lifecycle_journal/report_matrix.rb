# frozen_string_literal: true

module Master
  module Fix
    class Kernel
      # Validation of the assessment matrix ledger itself: schema, axis and cell
      # population, per-cell reading history, clean-streak bookkeeping and the
      # summary's claimed counts. Pure predicates over a report hash.
      class LifecycleJournal
        private

        def validate_assessment_matrix_report(report)
          return { "status" => "matrix_report_schema_unsupported" } unless report["schema_version"].to_i == 3

          status = report["status"].to_s
          return { "status" => "matrix_status_unknown" } unless %w[complete incomplete not_measured].include?(status)
          surface_failure = validate_surface_coverage_report(report, required: status == "complete")
          return surface_failure if surface_failure

          validate_assessment_matrix_ledger(report, status)
        rescue ArgumentError, TypeError, NoMethodError
          { "status" => "matrix_report_value_invalid" }
        end

        def validate_assessment_matrix_ledger(report, status)
          ledger = report["ledger"]
          unless ledger.is_a?(Hash)
            return { "status" => "matrix_ledger_missing" } if status == "complete"

            return
          end
          return { "status" => "matrix_ledger_schema_unsupported" } unless ledger["schema_version"].to_i == 2

          context, failure = assessment_matrix_context(ledger)
          return failure if failure

          keys, failure = assessment_matrix_cell_keys(context)
          return failure if failure

          counts, failure = assessment_matrix_cell_states(report, context, keys)
          return failure if failure

          validate_assessment_matrix_summary(report, status, context, counts)
        end

        def assessment_matrix_context(ledger)
          summary = ledger["summary"]
          cells = ledger["cells"]
          streams = Array(ledger["streams"]).map(&:to_s)
          surfaces = Array(ledger["surfaces"]).map(&:to_s)
          law_ids = ledger["laws"]
          unless summary.is_a?(Hash) && cells.is_a?(Array) && streams.any? && surfaces.any? && law_ids.is_a?(Array)
            return [nil, { "status" => "matrix_ledger_malformed" }]
          end
          return [nil, { "status" => "matrix_duplicate_axes" }] unless streams.uniq == streams && surfaces.uniq == surfaces
          unless law_ids.all? { |law| law.is_a?(String) && !law.strip.empty? } && law_ids.uniq == law_ids
            return [nil, { "status" => "matrix_law_population_invalid" }]
          end

          dimensions, failure = assessment_matrix_dimensions(summary, law_ids, streams, surfaces, cells)
          return [nil, failure] if failure

          [{
            summary:, cells:, streams:, surfaces:, law_ids:,
            allowed_readings: %w[assessed_clean violation_found opportunity_found not_applicable inconclusive],
            **dimensions,
          }, nil]
        end

        def assessment_matrix_dimensions(summary, law_ids, streams, surfaces, cells)
          required_clean_passes = Integer(summary["clean_passes_required"])
          generation = Integer(summary["generation"])
          last_mutation = Integer(summary["last_mutation_iteration"])
          laws = Integer(summary["laws"])
          expected_cells = Integer(summary["expected_cells"])
          return [nil, { "status" => "matrix_dimensions_invalid" }] unless required_clean_passes.positive? && laws.positive?
          return [nil, { "status" => "matrix_law_population_mismatch" }] unless law_ids.size == laws
          unless expected_cells == laws * streams.size * surfaces.size && cells.size == expected_cells
            return [nil, { "status" => "matrix_cell_count_mismatch" }]
          end

          [{ required_clean_passes:, generation:, last_mutation:, laws:, expected_cells: }, nil]
        end

        def assessment_matrix_cell_keys(context)
          keys = context[:cells].map do |cell|
            return [nil, { "status" => "matrix_cell_malformed" }] unless cell.is_a?(Hash)

            law = cell["law"].to_s
            stream = cell["stream"].to_s
            surface = cell["surface"].to_s
            if [law, stream, surface].any?(&:empty?)
              return [nil, { "status" => "matrix_cell_identity_missing" }]
            end
            unless context[:streams].include?(stream) && context[:surfaces].include?(surface)
              return [nil, { "status" => "matrix_cell_out_of_domain" }]
            end

            [law, stream, surface]
          end
          return [nil, { "status" => "matrix_duplicate_cells" }] unless keys.uniq.size == keys.size
          return [nil, { "status" => "matrix_law_count_mismatch" }] unless keys.map(&:first).uniq.size == context[:laws]

          expected = context[:law_ids].product(context[:streams], context[:surfaces]).to_set
          return [nil, { "status" => "matrix_cartesian_product_mismatch" }] unless keys.to_set == expected

          [keys, nil]
        end

        def assessment_matrix_cell_states(report, context, keys)
          totals = {
            recorded_cells: 0, unassessed_cells: 0, inconclusive_cells: 0,
            finding_cells: 0, complete: true, clean: true,
          }
          context[:cells].each_with_index do |cell, index|
            state, failure = assessment_matrix_cell_state(report, cell, keys[index], context)
            return [nil, failure] if failure

            %i[recorded_cells unassessed_cells inconclusive_cells finding_cells].each do |key|
              totals[key] += state[key]
            end
            totals[:complete] &&= state[:complete]
            totals[:clean] &&= state[:clean]
          end
          [totals, nil]
        end

        def assessment_matrix_cell_state(report, cell, key, context)
          reading_state, failure = assessment_matrix_cell_readings(cell, key, context)
          return [nil, failure] if failure

          readings = reading_state[:readings]
          return [{ recorded_cells: 0, unassessed_cells: 1, inconclusive_cells: 0,
                    finding_cells: 0, complete: false, clean: false }, nil] if readings.empty?

          failure = validate_assessment_matrix_reading_history(report, readings, key, context)
          return [nil, failure] if failure

          streak = assessment_matrix_clean_streak(readings, context)
          return [nil, { "status" => "matrix_clean_streak_mismatch", "cell" => key }] unless
            Integer(cell["clean_streak"]) == streak

          [assessment_matrix_cell_verdict(reading_state, streak, context), nil]
        end

        def assessment_matrix_cell_readings(cell, key, context)
          readings = cell["readings"]
          return [nil, { "status" => "matrix_readings_malformed", "cell" => key }] unless readings.is_a?(Array)

          cell_status = cell["status"].to_s
          unless (context[:allowed_readings] + ["pending"]).include?(cell_status)
            return [nil, { "status" => "matrix_cell_status_unknown", "cell" => key }]
          end
          if readings.empty?
            return [nil, { "status" => "matrix_pending_has_readings", "cell" => key }] unless cell_status == "pending"

            return [{ status: cell_status, readings:, latest: nil }, nil]
          end

          latest = readings.last
          unless latest.is_a?(Hash) && latest["status"].to_s == cell_status
            return [nil, { "status" => "matrix_latest_reading_mismatch", "cell" => key }]
          end
          [{ status: cell_status, readings:, latest: }, nil]
        end

        def validate_assessment_matrix_reading_history(report, readings, key, context)
          previous_iteration = 0
          previous_generation = 0
          readings.each do |reading|
            failure, iteration, generation = assessment_matrix_reading_failure(
              report, reading, key, context, previous_iteration, previous_generation
            )
            return failure if failure

            previous_iteration = iteration
            previous_generation = generation
          end
          nil
        end

        def assessment_matrix_reading_failure(report, reading, key, context, previous_iteration, previous_generation)
          return [{ "status" => "matrix_reading_malformed", "cell" => key }, nil, nil] unless reading.is_a?(Hash)

          iteration = Integer(reading["iteration"])
          generation = Integer(reading["generation"])
          reading_status = reading["status"].to_s
          failure = assessment_matrix_reading_order_failure(
            key, iteration, generation, reading_status, context, previous_iteration, previous_generation
          )
          return [failure, nil, nil] if failure

          failure = assessment_matrix_opportunity_receipt_failure(report, reading, key, reading_status)
          return [failure, nil, nil] if failure

          failure = assessment_matrix_reading_content_failure(reading, key, reading_status)
          return [failure, nil, nil] if failure

          [nil, iteration, generation]
        end

        def assessment_matrix_reading_order_failure(key, iteration, generation, status, context, previous_iteration, previous_generation)
          return if iteration.positive? && iteration > previous_iteration && generation >= previous_generation &&
                    generation <= context[:generation] && context[:allowed_readings].include?(status)

          { "status" => "matrix_reading_order_invalid", "cell" => key }
        end

        def assessment_matrix_opportunity_receipt_failure(report, reading, key, status)
          required = key == %w[CONVERGENCE_OPPORTUNITY lexical_opportunities whole_file] &&
                     %w[assessed_clean opportunity_found].include?(status)
          return unless required

          failure = validate_opportunity_reading(report, reading)
          failure&.merge("cell" => key)
        end

        def assessment_matrix_reading_content_failure(reading, key, status)
          evidence = Array(reading["evidence"])
          findings = Array(reading["findings"])
          reason = reading["reason"].to_s.strip
          return { "status" => "matrix_clean_without_evidence", "cell" => key } if status == "assessed_clean" && evidence.empty?
          return { "status" => "matrix_reason_missing", "cell" => key } if %w[not_applicable inconclusive].include?(status) && reason.empty?
          if %w[violation_found opportunity_found].include?(status) && evidence.empty? && findings.empty?
            return { "status" => "matrix_finding_without_evidence", "cell" => key }
          end
        end

        def assessment_matrix_clean_streak(readings, context)
          readings.reverse.take_while do |reading|
            reading["status"] == "assessed_clean" &&
              reading["generation"].to_i == context[:generation] &&
              reading["iteration"].to_i > context[:last_mutation]
          end.size
        end

        def assessment_matrix_cell_verdict(reading_state, streak, context)
          status = reading_state[:status]
          state = {
            recorded_cells: 1, unassessed_cells: 0, inconclusive_cells: 0,
            finding_cells: 0,
          }
          state[:inconclusive_cells] = 1 if status == "inconclusive"
          state[:finding_cells] = 1 if %w[violation_found opportunity_found].include?(status)
          state.merge(assessment_matrix_cell_completion(status, reading_state[:latest], streak, context))
        end

        def assessment_matrix_cell_completion(status, latest, streak, context)
          complete = true
          clean = true
          case status
          when "inconclusive", "violation_found", "opportunity_found"
            clean = false
          when "not_applicable"
            complete = false unless latest["generation"].to_i == context[:generation] &&
                                    !latest["reason"].to_s.strip.empty?
            clean = false unless complete
          when "assessed_clean"
            complete = false unless streak >= context[:required_clean_passes] &&
                                    latest["generation"].to_i == context[:generation] &&
                                    latest["iteration"].to_i > context[:last_mutation]
            clean = false unless complete
          else
            complete = false
            clean = false
          end
          { complete:, clean: }
        end

        def validate_assessment_matrix_summary(report, status, context, counts)
          counts.slice(:recorded_cells, :unassessed_cells, :inconclusive_cells, :finding_cells).each do |key, actual|
            return { "status" => "matrix_summary_count_mismatch", "field" => key.to_s } unless
              Integer(context[:summary][key.to_s]) == actual
          end
          failure = validate_assessment_matrix_stream_summary(context)
          return failure if failure

          complete = counts[:complete] && assessment_matrix_cells_complete?(context)
          clean = counts[:clean] && complete && context[:cells].all? do |cell|
            %w[assessed_clean not_applicable].include?(cell["status"])
          end
          unless context[:summary]["complete"] == complete && context[:summary]["clean"] == clean
            return { "status" => "matrix_summary_truth_mismatch" }
          end
          surface_coverage = report["surface_coverage"]
          surface_complete = surface_coverage.is_a?(Hash) && surface_coverage["complete"] == true
          unless (status == "complete") == (clean && surface_complete)
            return { "status" => "matrix_status_claim_mismatch" }
          end
          nil
        end

        def validate_assessment_matrix_stream_summary(context)
          stream_summary = context[:summary]["streams"]
          return { "status" => "matrix_stream_summary_missing" } unless stream_summary.is_a?(Hash)
          return { "status" => "matrix_stream_population_mismatch" } unless stream_summary.keys.sort == context[:streams].sort

          context[:streams].each do |stream|
            rows = context[:cells].select { |cell| cell["stream"] == stream }
            stream_row = stream_summary[stream]
            return { "status" => "matrix_stream_summary_malformed", "stream" => stream } unless stream_row.is_a?(Hash)
            return { "status" => "matrix_stream_cell_count_mismatch", "stream" => stream } unless
              Integer(stream_row["cells"]) == rows.size
            states = stream_row["states"]
            return { "status" => "matrix_stream_states_missing", "stream" => stream } unless states.is_a?(Hash)
            (context[:allowed_readings] + ["pending"]).each do |state|
              actual = rows.count { |cell| cell["status"] == state }
              return { "status" => "matrix_stream_state_count_mismatch", "stream" => stream, "state" => state } unless
                Integer(states[state]) == actual
            end
          end
          nil
        end

        def assessment_matrix_cells_complete?(context)
          context[:cells].all? do |cell|
            (cell["status"] == "not_applicable" &&
              cell["readings"].last&.fetch("generation", nil).to_i == context[:generation]) ||
              (cell["status"] == "assessed_clean" &&
                cell["clean_streak"].to_i >= context[:required_clean_passes])
          end
        end
      end
    end
  end
end
