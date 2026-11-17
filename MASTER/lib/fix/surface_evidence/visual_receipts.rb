# frozen_string_literal: true

module Master
  module Fix
    class SurfaceEvidence
      # Receipt builders for the browser-observed surfaces: rendered UI
      # coverage from a VisualPass result and the safe interactive journey
      # probes, plus the capture-row validation they share.
      private

      def target_has_frontend?
        @plan.sources.any? do |source|
          path = source.path
          path.match?(%r{(?:\A|/)(?:app/views|views|templates|frontend|src|public)/}) &&
            %w[.erb .html .htm .css .scss .js .mjs .ts .tsx .jsx].include?(File.extname(path).downcase)
        end || rails_target? && @plan.sources.any? { |source| %w[.erb .html .htm .css .scss].include?(File.extname(source.path).downcase) }
      end

      def rendered_ui_receipt
        return receipt("not_applicable", reason: "target inventory has no declared front-end surface") unless target_has_frontend?
        return receipt("inconclusive", reason: "rendered browser evidence was not produced for this pass") unless @visual_result

        if @visual_result.respond_to?(:err?) && @visual_result.err?
          return receipt("inconclusive", reason: @visual_result.message.to_s[0, 220],
            evidence: { "method" => "VisualPass", "result" => "error" })
        end

        value = result_value(@visual_result)
        return receipt("inconclusive", reason: "VisualPass returned no result payload") unless value.is_a?(Hash)
        rendered_ui_payload_receipt(value)
      rescue StandardError => e
        receipt("inconclusive", reason: "rendered UI receipt failed: #{error_text(e)}")
      end

      def rendered_ui_payload_receipt(value)
        coverage = value[:coverage] || value["coverage"] || {}
        captures = Array(value[:surface_evidence] || value["surface_evidence"])
        expected = Array(coverage[:expected] || coverage["expected"])
        actual = Array(coverage[:captured] || coverage["captured"])
        missing = Array(coverage[:missing] || coverage["missing"])
        unless expected.any? && missing.empty? && (expected - actual).empty? && captures.size >= expected.size
          return rendered_ui_incomplete_receipt(expected, actual, missing, captures)
        end
        broken = captures.reject { |row| valid_rendered_capture?(row) }
        return rendered_ui_broken_receipt(broken) if broken.any?

        rendered_ui_clean_receipt(captures, expected, actual, missing)
      end

      def rendered_ui_incomplete_receipt(expected, actual, missing, captures)
        receipt("inconclusive", reason: "rendered surface coverage incomplete",
          evidence: { "expected" => expected, "captured" => actual, "missing" => missing, "capture_records" => captures.size })
      end

      def rendered_ui_broken_receipt(broken)
        receipt("inconclusive", reason: "rendered surface lacked a stable screenshot or geometry receipt",
          evidence: { "broken" => broken.first(8) })
      end

      def rendered_ui_clean_receipt(captures, expected, actual, missing)
        receipt("assessed_clean", evidence: {
          "method" => "VisualPass CDP rendered capture plus geometry and viewport coverage",
          "coverage" => { "expected" => expected, "captured" => actual, "missing" => missing },
          "surfaces" => captures.map { |row| compact_visual_row(row) },
        }, counts: { "surfaces" => captures.size })
      end

      def interactive_receipt
        return receipt("not_applicable", reason: "target inventory has no declared front-end surface") unless target_has_frontend?
        return receipt("inconclusive", reason: "interactive behavior was not measured without a rendered browser result") unless @visual_result
        return receipt("inconclusive", reason: @visual_result.message.to_s[0, 220]) if @visual_result.respond_to?(:err?) && @visual_result.err?

        value = result_value(@visual_result)
        captures = Array(value && (value[:surface_evidence] || value["surface_evidence"]))
        return receipt("inconclusive", reason: "rendered browser result contains no interaction receipts") if captures.empty?

        unresolved = []
        violations = []
        action_count = 0
        captures.each { |row| action_count += collect_interaction_outcomes(row, unresolved, violations) }
        interactive_summary_receipt(captures, unresolved, violations, action_count)
      rescue StandardError => e
        receipt("inconclusive", reason: "interactive behavior receipt failed: #{error_text(e)}")
      end

      def collect_interaction_outcomes(row, unresolved, violations)
        journey = row_value(row, "journey")
        return 0 unless journey.is_a?(Hash)

        actions = Array(row_value(journey, "actions"))
        collect_journey_outcomes(row, journey, actions, unresolved, violations)
        actions.size
      end

      def collect_journey_outcomes(row, journey, actions, unresolved, violations)
        case row_value(journey, "status").to_s
        when "not_applicable" then nil
        when "assessed_clean" then collect_clean_journey_outcomes(row, actions, unresolved, violations)
        when "violation_found" then collect_failed_journey_outcomes(row, journey, unresolved, violations)
        else
          unresolved << { "surface" => row_value(row, "id"), "reason" => row_value(journey, "reason") || "interaction probe inconclusive" }
        end
      end

      def collect_clean_journey_outcomes(row, actions, unresolved, violations)
        failures = actions.select { |action| row_value(action, "status").to_s == "violation_found" }
        unknown = actions.reject { |action| %w[assessed_clean violation_found].include?(row_value(action, "status").to_s) }
        violations.concat(failures.map { |action| { "surface" => row_value(row, "id"), "action" => action } })
        unresolved << { "surface" => row_value(row, "id"), "actions" => unknown.first(5) } if unknown.any?
      end

      def collect_failed_journey_outcomes(row, journey, unresolved, violations)
        violations.concat(Array(row_value(journey, "failures")).map { |action| { "surface" => row_value(row, "id"), "action" => action } })
        unresolved << { "surface" => row_value(row, "id"), "reason" => "journey detected a behavioral failure" } if Array(row_value(journey, "failures")).empty?
      end

      def interactive_summary_receipt(captures, unresolved, violations, action_count)
        return interactive_violation_receipt(violations) if violations.any?
        return interactive_unresolved_receipt(unresolved) if unresolved.any?
        return interactive_no_actions_receipt(captures) if action_count.zero?

        receipt("assessed_clean", evidence: {
          "method" => "safe same-origin browser journey probes; destructive and non-GET form actions are excluded",
          "surfaces" => captures.map { |row| row_value(row, "id") },
          "action_count" => action_count,
          "journey_sha256" => digest_json(captures.map { |row| compact_visual_row(row) }),
        }, counts: { "surfaces" => captures.size, "actions" => action_count })
      end

      def interactive_violation_receipt(violations)
        receipt("violation_found", reason: "one or more safe interaction journeys failed",
          evidence: { "violations" => violations.first(10) }, findings: violations.first(30))
      end

      def interactive_unresolved_receipt(unresolved)
        receipt("inconclusive", reason: "interaction evidence missing or incomplete for one or more captured surfaces",
          evidence: { "unresolved" => unresolved.first(10) })
      end

      def interactive_no_actions_receipt(captures)
        receipt("not_applicable", reason: "rendered surfaces exposed no safe, measurable interactive controls",
          evidence: { "surfaces" => captures.map { |row| row_value(row, "id") }, "actions" => 0 })
      end

      def valid_rendered_capture?(row)
        return false unless row_status(row, "rendered_status") == "assessed_clean"
        return false unless row_value(row, "screenshot_sha256").to_s.match?(/\A[a-f0-9]{64}\z/)
        return false unless row_value(row, "geometry_sha256").to_s.match?(/\A[a-f0-9]{64}\z/)

        count = Integer(row_value(row, "element_count"))
        count >= 0
      rescue ArgumentError, TypeError
        false
      end

      def compact_visual_row(row)
        journey = row_value(row, "journey")
        {
          "id" => row_value(row, "id"),
          "app" => row_value(row, "app"),
          "viewport" => row_value(row, "viewport"),
          "rendered_status" => row_value(row, "rendered_status"),
          "screenshot_sha256" => row_value(row, "screenshot_sha256"),
          "geometry_sha256" => row_value(row, "geometry_sha256"),
          "element_count" => row_value(row, "element_count"),
          "journey_status" => row_value(journey, "status"),
          "journey_actions" => Array(row_value(journey, "actions")).map do |action|
            action.select { |key, _| %w[kind selector label status changed from to].include?(key.to_s) }
          end,
        }.compact
      end
    end
  end
end
