# frozen_string_literal: true

module Cognition
  # What deserves scarce internal attention, scored from the event, how novel
  # it is, and how aroused the affect model already is. A salience heuristic
  # borrowed from global-workspace architectures, not a claim to reproduce
  # biological attention.
  #
  # Every row names an event Mind#observe_ledger or the conversation reports.
  # A weight for an event nobody reports is a salience the layer never
  # computes, so a new row lands with its reporter.
  class Attention
    EVENT_WEIGHTS = {
      "refusal" => 0.95,
      "turn:failed" => 0.8,
      "turn:answered" => 0.5,
      "effect:exec" => 0.35,
      "llm:call" => 0.35
    }.freeze

    DEFAULT_WEIGHT = 0.25

    def score(event:, payload:, prediction_error:, affect:)
      base = EVENT_WEIGHTS.fetch(event.to_s, DEFAULT_WEIGHT)
      novelty = prediction_error.to_f.clamp(0.0, 1.0)
      arousal = affect.fetch("arousal", 0.25).to_f.clamp(0.0, 1.0)
      (base * 0.55 + novelty * 0.3 + arousal * 0.15 + urgency(payload)).clamp(0.0, 1.0)
    end

    private

    def urgency(payload)
      payload.is_a?(Hash) && (payload[:severity] || payload["severity"]).to_s == "critical" ? 0.35 : 0.0
    end
  end
end
