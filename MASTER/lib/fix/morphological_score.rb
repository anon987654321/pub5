# frozen_string_literal: true

module Master
  module Fix
    # MorphologicalScore — scores divergent probes for ROBUSTNESS_morphological_exploration.
    #
    # Given a list of probe results (each a Hash with optional keys), returns
    # a ranked list with total score and component breakdown. Does not launch
    # agents; it only ranks evidence that already exists.
    #
    # Missing dimensions are unknown, not free points. A probe without complete
    # causal, cost, tangle and rollback evidence remains provisional and cannot win.
    #   law_alignment (0..10), causal_trace_quality (0..10), profile_cost (lower better),
    #   tangle_delta (negative = improvement), antigen_hits (lower better),
    #   evidence_count, rollback_ready (bool), scope_clarity (0..10)
    module MorphologicalScore
      WEIGHTS = {
        law_alignment: 20,
        causal_trace_quality: 18,
        profile_cost: 15,
        tangle_delta: 12,
        antigen_hits: 12,
        evidence_count: 10,
        rollback_ready: 8,
        scope_clarity: 5,
      }.freeze

      MIN_WINNER = 55
      REQUIRED = WEIGHTS.keys.freeze

      module_function

      def rank(probes)
        raise ArgumentError, "probes must be an Array" unless probes.is_a?(Array)

        scored = probes.map.with_index { |probe, i| score_one(probe, i) }
        scored.sort_by { |s| [-s[:total], s[:index]] }
      end

      def score_one(probe, index = 0)
        probe = probe.transform_keys(&:to_s) if probe.respond_to?(:transform_keys)
        probe = {} unless probe.is_a?(Hash)

        measured = {
          law_alignment: !probe["law_alignment"].nil?,
          causal_trace_quality: !probe["causal_trace_quality"].nil?,
          profile_cost: !probe["profile_cost"].nil?,
          tangle_delta: !probe["tangle_delta"].nil?,
          antigen_hits: !probe["antigen_hits"].nil?,
          evidence_count: !probe["evidence_count"].nil?,
          rollback_ready: probe.key?("rollback_ready") && !probe["rollback_ready"].nil?,
          scope_clarity: !probe["scope_clarity"].nil?,
        }
        components = {
          law_alignment: scale(probe["law_alignment"], 0, 10, WEIGHTS[:law_alignment]),
          causal_trace_quality: scale(probe["causal_trace_quality"], 0, 10, WEIGHTS[:causal_trace_quality]),
          profile_cost: invert_cost(probe["profile_cost"], WEIGHTS[:profile_cost]),
          tangle_delta: tangle_score(probe["tangle_delta"], WEIGHTS[:tangle_delta]),
          antigen_hits: invert_hits(probe["antigen_hits"], WEIGHTS[:antigen_hits]),
          evidence_count: scale(probe["evidence_count"], 0, 20, WEIGHTS[:evidence_count]),
          rollback_ready: probe["rollback_ready"] == true ? WEIGHTS[:rollback_ready] : 0,
          scope_clarity: scale(probe["scope_clarity"], 0, 10, WEIGHTS[:scope_clarity]),
        }

        total = components.values.sum
        missing = REQUIRED.reject { |dimension| measured.fetch(dimension) }
        measured_weight = measured.sum { |dimension, present| present ? WEIGHTS.fetch(dimension) : 0 }
        coverage = measured_weight.to_f / WEIGHTS.values.sum
        {
          index: index,
          id: probe["id"] || probe["name"] || "probe-#{index}",
          total: total.round(2),
          coverage: (coverage * 100).round(1),
          measured_dimensions: measured.select { |_dimension, present| present }.keys,
          missing_dimensions: missing,
          qualified: missing.empty? && total >= MIN_WINNER,
          components: components,
          probe: probe,
        }
      end

      def winner(probes)
        ranked = rank(probes)
        ranked.find { |s| s[:qualified] }
      end

      def scale(value, min, max, weight)
        return 0 if value.nil?
        v = value.to_f.clamp(min, max)
        return 0 if max == min
        ((v - min) / (max - min)) * weight
      end

      def invert_cost(cost, weight)
        return 0 if cost.nil?
        # Lower cost is better. Map 0..high to weight..0 roughly.
        c = [cost.to_f, 0].max
        factor = 1.0 / (1.0 + (c / 100.0))
        factor * weight
      end

      def tangle_score(delta, weight)
        return 0 if delta.nil?
        # A negative delta means fewer tangles; zero is neutral, positive is regression.
        d = delta.to_f
        if d.negative?
          weight * (d.abs / (5.0 + d.abs))
        elsif d.zero?
          weight * 0.5
        else
          weight * (0.3 / (1.0 + d / 5.0))
        end
      end

      def invert_hits(hits, weight)
        return 0 if hits.nil?
        return weight if hits.to_i <= 0
        weight * (1.0 / (1.0 + hits.to_i))
      end
    end
  end
end
