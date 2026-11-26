# frozen_string_literal: true

require_relative "layout_score_store"

module Master
  module Fix
    # Re-renders surfaces through the same capture API VisualCustody uses and
    # scores them, so a candidate change can be judged on pixels it produced.
    # `measure` is the only method that needs Chrome; callers inject it in tests.
    module LayoutScoreRender
      EPSILON = 0.05

      module_function

      # [[surface, payload], ...] for the given surfaces, in one browser session.
      def measure(surfaces, root:)
        require_relative "../../checks/support/geometry_probe"
        require_relative "../../checks/support/surface_probes"
        return [] unless Deploy::GeometryProbe.available?

        rows = []
        Deploy::GeometryProbe.with_browser(root:, warm: surfaces) do |cdp|
          surfaces.each { |s| rows << [s, Deploy::SurfaceProbes.attach(cdp, s, Deploy::GeometryProbe.walk(cdp, s))] }
        end
        rows
      end

      def scores(measured, root:)
        valid_measurements(measured).to_h { |surface, payload| [surface.id, LayoutScoreStore.measure(root, payload).score] }
      end

      # A failed navigation or empty geometry is missing evidence, not a low score.
      def valid_measurements(measured)
        measured.select { |_surface, payload| valid_payload?(payload) }
      end

      def valid_payload?(payload)
        return false unless payload.is_a?(Hash) && !payload["error"]

        status = Integer(payload.fetch("status", 0), exception: false)
        return false unless status && (status.zero? || status.between?(200, 399))
        return false unless %w[vw vh].all? { |key| positive_number?(payload[key]) }

        Array(payload["elements"]).any? do |element|
          next false unless element.is_a?(Hash) && element["visible"] != false && element["onscreen"] != false

          rect = element["rect"]
          rect.is_a?(Hash) && %w[w h].all? { |key| positive_number?(rect[key]) }
        end
      end

      def positive_number?(value) = value.is_a?(Numeric) && value.finite? && value.positive?

      # A re-render check for ScaleSnap.apply: true when no surface scores
      # lower than it did when the hook was built.
      def rescore_hook(surfaces, root:, measurer: method(:measure))
        expected = surfaces.map(&:id).uniq.sort
        before = scores(measurer.call(surfaces, root:), root:)
        complete = !expected.empty? && before.keys.sort == expected
        lambda do |_path|
          after = scores(measurer.call(surfaces, root:), root:)
          complete && after.keys.sort == expected && before.all? { |id, score| after.fetch(id) >= score - EPSILON }
        end
      end
    end
  end
end
