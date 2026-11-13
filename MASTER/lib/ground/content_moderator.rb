# frozen_string_literal: true

require_relative "../result"
require_relative "content_analysis"

module Master
  module Ground
    # Turns wording matches into a bounded review recommendation. It has no
    # write client and cannot hide, delete, ban, or notify anyone.
    class ContentModerator
      DEFAULTS = { review_threshold: 20, repeat_offender_multiplier: 2.0 }.freeze

      def initialize(config: {})
        @config = DEFAULTS.merge(config.to_h.transform_keys(&:to_sym))
        threshold = Integer(@config.fetch(:review_threshold))
        multiplier = Float(@config.fetch(:repeat_offender_multiplier))
        raise ArgumentError, "review_threshold must be positive" unless threshold.positive?
        raise ArgumentError, "repeat_offender_multiplier must be finite and >= 1" unless multiplier.finite? && multiplier >= 1
        @config[:review_threshold] = threshold
        @config[:repeat_offender_multiplier] = multiplier
      end

      def analyze(content:, prior_violations: 0)
        return Result.err("content_moderator: content must be a mapping", category: :validation) unless content.is_a?(Hash)
        prior = Integer(prior_violations)
        return Result.err("content_moderator: prior_violations must be 0..50", category: :validation) unless prior.between?(0, 50)

        body = (content[:text] || content["text"]).to_s
        return Result.err("content_moderator: content text is empty", category: :validation) if body.strip.empty?
        counts = ContentAnalysis.scan(body)
        base = ContentAnalysis.score(counts)
        score = (base * (@config[:repeat_offender_multiplier]**prior)).round
        review = score >= @config[:review_threshold]
        Result.ok(
          schema: 1, counts:, weighted_score: score,
          recommendation: review ? "REVIEW" : "NO_MATCH",
          severity: ContentAnalysis.severity(counts),
          evidence: counts.reject { |_key, value| value.zero? },
          human_authorization_required: review,
          action_performed: false,
          limitations: ["keyword signals can be wrong in quotation, counterspeech and context"],
        )
      rescue ArgumentError, TypeError => error
        Result.err("content_moderator: #{error.message}", category: :validation)
      rescue StandardError => error
        Result.err("content_moderator: #{error.class}: #{error.message}", category: :infrastructure)
      end
    end
  end
end
