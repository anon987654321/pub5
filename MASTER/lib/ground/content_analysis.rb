# frozen_string_literal: true

module Master
  module Ground
    # Deterministic wording signals shared by moderation and risk review.
    # These patterns are deliberately not a classifier: context, quotation,
    # counterspeech and dialect can all produce false positives.
    module ContentAnalysis
      HARASSMENT = /\b(?:kill|death\s+threat|stalk|harass|watch(?:ing)?|threaten|attack(?:ing)?|hunt|find\s+you|know\s+where\s+you\s+live)\b/i.freeze
      ABUSIVE = /\b(?:stupid|idiot|moron|dumb|loser|pathetic|disgusting|worthless|inferior|subhuman)\b/i.freeze
      SPAM = /\b(?:click\s+here|buy\s+now|limited\s+time|act\s+now|free\s+money|make\s+money\s+fast|work\s+from\s+home)\b/i.freeze
      SCAM = /(?:you(?:'ve|\s+have)\s+won|claim\s+your\s+prize|send\s+money|wire\s+transfer|bank\s+account|credit\s+card\s+number)/i.freeze
      ESCALATION = /\b(?:again|still|won't\s+stop|can't\s+stop|every\s+day|all\s+the\s+time|constantly|repeatedly|over\s+and\s+over|never\s+stop)\b/i.freeze
      BANNED = /\b(?:nazi|hitler|kkk|white\s+supremac(?:y|ist)|racial\s+slur)\b/i.freeze
      PROFANE = /\b(?:fuck|shit|bitch|bastard|piss)\b/i.freeze
      THREATENING = HARASSMENT

      KEYS = %i[harassment abusive spam scam escalation banned profane].freeze
      module_function

      def scan(text)
        body = text.to_s
        KEYS.to_h do |key|
          pattern = const_get(key.to_s.upcase)
          [key, body.scan(pattern).size]
        end.freeze
      end

      def severity(counts)
        return "CRITICAL" if counts.fetch(:banned, 0).positive? || counts.fetch(:scam, 0).positive?
        return "HIGH" if counts.fetch(:harassment, 0).positive?
        return "MEDIUM" if %i[abusive spam profane].any? { |key| counts.fetch(key, 0).positive? }

        "LOW"
      end

      def score(counts)
        counts.fetch(:banned, 0) * 50 + counts.fetch(:scam, 0) * 40 +
          counts.fetch(:harassment, 0) * 25 + counts.fetch(:abusive, 0) * 8 +
          counts.fetch(:escalation, 0) * 5 + counts.fetch(:spam, 0) * 3 +
          counts.fetch(:profane, 0)
      end
    end
  end
end
