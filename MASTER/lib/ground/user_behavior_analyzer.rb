# frozen_string_literal: true

require "fileutils"
require "json"
require "openssl"
require "time"
require_relative "../result"
require_relative "../io/atomic_write"
require_relative "../boot/paths"
require_relative "content_analysis"

module Master
  module Ground
    # In-memory behavior scoring with explicitly consented, pseudonymous
    # cross-platform aggregates. Raw messages and raw subject identifiers are
    # never written. A score is a review signal, not a sanction.
    class UserBehaviorAnalyzer
      include ::Master::Io::AtomicWrite

      PURPOSE = "cross-platform behavioral risk analysis".freeze
      DEFAULTS = {
        message_frequency_threshold: 50.0,
        analysis_window_hours: 24,
        cross_platform_tracking: false,
      }.freeze
      TRACKER_NAME = File.join("user_behavior", "tracker.json")
      MAX_ROWS_PER_SUBJECT = 50
      MAX_LEDGER_BYTES = 2 * 1024 * 1024
      MAX_TRACKED_SUBJECTS = 2_000

      def initialize(root: MasterPaths.state, config: {}, consent_check: nil, identity_key: nil,
                     clock: -> { Time.now.utc })
        @root = File.expand_path(root)
        @config = DEFAULTS.merge(config.to_h.transform_keys(&:to_sym))
        @consent_check = consent_check
        @identity_key = identity_key.to_s
        @clock = clock
        @tracker_path = File.join(@root, TRACKER_NAME)
        FileUtils.mkdir_p(File.dirname(@tracker_path), mode: 0o700)
        File.chmod(0o700, File.dirname(@tracker_path))
        @mutex = Mutex.new
        validate_config!
      end

      def analyze(messages:, platform:, user_id:)
        rows = normalize(messages)
        return Result.err("user_behavior_analyzer: no valid messages", category: :validation) if rows.empty?
        return Result.err("user_behavior_analyzer: user_id is required", category: :validation) if user_id.to_s.strip.empty?

        cutoff = now - (@config[:analysis_window_hours] * 3600)
        window = rows.select { |row| row[:at] >= cutoff && row[:at] <= now }
        return Result.err("user_behavior_analyzer: no messages in the analysis window", category: :validation) if window.empty?

        counts = window.map { |row| ContentAnalysis.scan(row[:text]) }
        keyword_total = counts.sum { |count| count[:harassment] + count[:abusive] + count[:banned] + count[:profane] }
        escalation = counts.sum { |count| count[:escalation] }
        frequency = window.size.to_f / @config[:analysis_window_hours]
        score = (keyword_total * 10) + (escalation * 5) +
                ([frequency - @config[:message_frequency_threshold], 0].max * 2).round
        result = {
          schema: 1, messages: window.size, frequency_per_hour: frequency.round(2),
          keyword_total:, escalation:, score:, risk_level: risk_level(score),
          recommendation: score >= 20 ? "REVIEW" : "NORMAL",
          action_performed: false, not_run: [],
        }
        if @config[:cross_platform_tracking]
          if tracking_allowed?(user_id)
            track(user_id, platform, result)
          else
            result[:not_run] << "cross-platform history: explicit subject consent and an identity key are required"
          end
        else
          result[:not_run] << "cross-platform history: disabled by default"
        end
        Result.ok(result)
      rescue ArgumentError => error
        Result.err("user_behavior_analyzer: #{error.message}", category: :validation)
      rescue StandardError => error
        Result.err("user_behavior_analyzer: #{error.class}: #{error.message}", category: :infrastructure)
      end

      def aggregate(user_id:)
        return Result.err("user_behavior_analyzer: tracking is not enabled or consented", category: :policy) unless tracking_allowed?(user_id)

        rows = with_lock { load.fetch("users", {}).fetch(subject_key(user_id), []) }
        return Result.err("user_behavior_analyzer: no records", category: :validation) if rows.empty?

        scores = rows.map { |row| row.fetch("score").to_i }
        Result.ok(
          schema: 1, platforms: rows.map { |row| row.fetch("platform") }.uniq.sort,
          observations: rows.size, max_score: scores.max,
          mean_score: (scores.sum.to_f / scores.size).round(1),
          aggregate_risk: risk_level(scores.max),
        )
      rescue StandardError => error
        Result.err("user_behavior_analyzer: #{error.class}: #{error.message}", category: :infrastructure)
      end

      # Erasure is available even after consent withdrawal, provided the same
      # HMAC key is configured; the raw identifier is not stored.
      def forget(user_id:)
        return Result.err("user_behavior_analyzer: identity key is unavailable", category: :policy) if @identity_key.bytesize < 32
        key = subject_key(user_id)
        with_lock do
          data = load
          removed = !data.fetch("users", {}).delete(key).nil?
          persist(data) if removed
          return Result.err("user_behavior_analyzer: no record", category: :validation) unless removed
        end
        Result.ok(removed: true)
      rescue StandardError => error
        Result.err("user_behavior_analyzer: #{error.class}: #{error.message}", category: :infrastructure)
      end

      private

      def validate_config!
        hours = Float(@config.fetch(:analysis_window_hours))
        threshold = Float(@config.fetch(:message_frequency_threshold))
        unless hours.finite? && hours.positive? && hours <= 168 && threshold.finite? && threshold >= 0
          raise ArgumentError, "analysis window or frequency threshold is invalid"
        end
        @config[:analysis_window_hours] = hours
        @config[:message_frequency_threshold] = threshold
      end

      def normalize(messages)
        Array(messages).first(500).filter_map do |row|
          next unless row.is_a?(Hash)
          at_value = row[:at] || row["at"]
          text = row[:text] || row["text"]
          next if text.nil?
          at = at_value.is_a?(Time) ? at_value.utc : Time.iso8601(at_value.to_s)
          { at:, text: text.to_s.byteslice(0, 4_000).to_s.scrub }
        rescue ArgumentError
          nil
        end
      end

      def tracking_allowed?(user_id)
        return false unless @config[:cross_platform_tracking] == true
        return false unless @identity_key.bytesize >= 32 && @consent_check.respond_to?(:call)
        @consent_check.call(user_id: user_id, purpose: PURPOSE) == true
      rescue StandardError
        false
      end

      def subject_key(user_id)
        OpenSSL::HMAC.hexdigest("SHA256", @identity_key, user_id.to_s)
      end

      def track(user_id, platform, analysis)
        value = platform.to_s
        raise ArgumentError, "platform must be a bounded identifier" unless value.match?(/\A[a-zA-Z0-9_.-]{1,40}\z/)
        with_lock do
          data = load
          identity = subject_key(user_id)
          rows = data.fetch("users").fetch(identity, [])
          if !data["users"].key?(identity) && data["users"].size >= MAX_TRACKED_SUBJECTS
            raise IOError, "behavior tracker reached its subject limit"
          end
          rows << {
            "at" => now.iso8601, "platform" => value,
            "score" => analysis[:score], "risk_level" => analysis[:risk_level],
          }
          data["users"][identity] = rows.last(MAX_ROWS_PER_SUBJECT)
          encoded = JSON.pretty_generate(data) + "\n"
          raise IOError, "behavior tracker would exceed its size limit" if encoded.bytesize > MAX_LEDGER_BYTES
          write_atomic(@tracker_path, encoded, mode: 0o600)
        end
      end

      def with_lock
        File.open("#{@tracker_path}.lock", File::RDWR | File::CREAT, 0o600) do |lock|
          lock.flock(File::LOCK_EX)
          yield
        ensure
          lock&.flock(File::LOCK_UN) rescue nil
        end
      end

      def load
        return { "schema" => 1, "users" => {} } unless File.exist?(@tracker_path)
        raise IOError, "behavior tracker must not be a symlink" if File.symlink?(@tracker_path)
        raise IOError, "behavior tracker exceeds #{MAX_LEDGER_BYTES} bytes" if File.size(@tracker_path) > MAX_LEDGER_BYTES
        data = JSON.parse(File.read(@tracker_path, encoding: "UTF-8"))
        raise IOError, "behavior tracker schema is invalid" unless data.is_a?(Hash) && data["schema"] == 1 && data["users"].is_a?(Hash)
        data
      rescue JSON::ParserError => error
        raise IOError, "behavior tracker is corrupt: #{error.message.lines.first}"
      end

      def persist(data) = write_atomic(@tracker_path, JSON.pretty_generate(data) + "\n", mode: 0o600)

      def risk_level(score)
        return "CRITICAL" if score >= 100
        return "HIGH" if score >= 50
        return "MEDIUM" if score >= 20
        "LOW"
      end

      def now
        value = @clock.call
        raise TypeError, "clock must return Time" unless value.is_a?(Time)
        value.utc
      end
    end
  end
end
