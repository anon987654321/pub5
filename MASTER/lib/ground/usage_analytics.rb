# frozen_string_literal: true

require "fileutils"
require "json"
require "time"
require_relative "../result"
require_relative "../io/atomic_write"
require_relative "../boot/paths"

module Master
  module Ground
    # First-party feature-usage aggregates. Each event is accepted only after
    # the owning app confirms the user's optional analytics consent. The user's
    # identifier is used only for that check and is never written to the ledger.
    class UsageAnalytics
      include ::Master::Io::AtomicWrite

      PURPOSE = "record aggregate first-party feature usage analytics".freeze
      STORE_NAME = File.join("usage_analytics", "events.ndjson")
      MAX_BYTES = 4 * 1024 * 1024
      MAX_EVENTS = 50_000
      SLUG = /\A[a-zA-Z0-9][a-zA-Z0-9_.:-]{0,79}\z/

      def initialize(root: MasterPaths.state, consent_check: nil, clock: -> { Time.now.utc })
        @root = File.expand_path(root)
        @path = File.join(@root, STORE_NAME)
        @lock_path = "#{@path}.lock"
        @consent_check = consent_check || ->(**) { false }
        @clock = clock
        FileUtils.mkdir_p(File.dirname(@path), mode: 0o700)
        File.chmod(0o700, File.dirname(@path))
      end

      def record(user_id:, feature:, action:, platform:, metadata: {})
        return Result.err("usage_analytics: analytics consent is not granted", category: :policy) unless consented?(user_id)
        values = [feature, action, platform].map { |value| value.to_s.strip }
        return Result.err("usage_analytics: feature, action and platform are required", category: :validation) unless values.all? { |value| SLUG.match?(value) }

        event = {
          "at" => now.iso8601, "feature" => values[0], "action" => values[1],
          "platform" => values[2], "metadata" => safe_metadata(metadata),
        }
        with_lock do
          rows = read_rows
          rows << event
          rows.shift while rows.size > MAX_EVENTS || encoded_size(rows) > MAX_BYTES
          write_atomic(@path, rows.map { |row| JSON.generate(row) }.join("\n") + (rows.empty? ? "" : "\n"), mode: 0o600)
        end
        Result.ok(event)
      rescue StandardError => error
        Result.err("usage_analytics: #{error.class}: #{error.message}", category: :infrastructure)
      end

      # The upper boundary is exclusive. No user-level count is calculated:
      # identifiers are intentionally not retained in this aggregate ledger.
      def report(since: now - 86_400, until_at: now)
        start_time = coerce_time(since)
        end_time = coerce_time(until_at)
        return Result.err("usage_analytics: invalid report window", category: :validation) unless start_time < end_time

        rows = with_lock { read_rows }
        selected = rows.select do |row|
          at = Time.iso8601(row.fetch("at"))
          at >= start_time && at < end_time
        end
        Result.ok(
          schema: 1, window: { since: start_time.iso8601, until: end_time.iso8601 },
          total_events: selected.size,
          feature_counts: count_by(selected, "feature"),
          action_counts: count_by(selected, "action"),
          platform_counts: count_by(selected, "platform"),
          distinct_users_by_feature: nil,
          not_run: ["distinct user counts: identifiers are not retained"],
        )
      rescue StandardError => error
        Result.err("usage_analytics: #{error.class}: #{error.message}", category: :infrastructure)
      end

      private

      def consented?(user_id)
        return false if user_id.to_s.strip.empty?

        @consent_check.call(user_id: user_id, purpose: PURPOSE) == true
      rescue StandardError
        false
      end

      def safe_metadata(metadata)
        return {} unless metadata.is_a?(Hash)

        allowed = %w[version duration_ms count]
        metadata.each_with_object({}) do |(key, value), output|
          name = key.to_s
          next unless allowed.include?(name)
          if name == "version"
            next unless value.is_a?(String) && value.match?(/\A[a-zA-Z0-9_.+-]{1,32}\z/)
          else
            next unless value.is_a?(Integer) && value.between?(0, 10**12)
          end
          output[name] = value
        end
      end

      def now
        value = @clock.call
        raise TypeError, "clock must return Time" unless value.is_a?(Time)
        value.utc
      end

      def coerce_time(value)
        time = value.is_a?(Time) ? value : Time.iso8601(value.to_s)
        time.utc
      rescue ArgumentError
        raise ArgumentError, "report boundaries must be Time or ISO-8601"
      end

      def with_lock
        File.open(@lock_path, File::RDWR | File::CREAT, 0o600) do |lock|
          lock.flock(File::LOCK_EX)
          yield
        ensure
          lock&.flock(File::LOCK_UN) rescue nil
        end
      end

      def read_rows
        return [] unless File.file?(@path)
        raise IOError, "analytics ledger is not a regular file" if File.symlink?(@path)
        raise IOError, "analytics ledger exceeds its size limit" if File.size(@path) > MAX_BYTES

        File.foreach(@path).filter_map do |line|
          next if line.strip.empty?
          JSON.parse(line).tap do |row|
            raise IOError, "analytics row is not an object" unless row.is_a?(Hash)
            raise IOError, "analytics row schema is invalid" unless %w[at feature action platform metadata].all? { |key| row.key?(key) }
          end
        end
      rescue JSON::ParserError => error
        raise IOError, "analytics ledger is corrupt: #{error.message.lines.first}"
      end

      def encoded_size(rows) = rows.sum { |row| JSON.generate(row).bytesize + 1 }
      def count_by(rows, key) = rows.group_by { |row| row.fetch(key) }.transform_values(&:size)
    end
  end
end
