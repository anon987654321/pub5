# frozen_string_literal: true

require "fileutils"
require "json"
require "securerandom"
require "time"
require_relative "../result"
require_relative "../io/atomic_write"
require_relative "../boot/paths"
require_relative "personal_permissions"

module Master
  module Ground
    # Private local inbox. Reading and writing notification contents requires
    # the existing explicit notifications permission. This class never pushes
    # notifications to a device or sends replies.
    class NotificationAggregator
      include ::Master::Io::AtomicWrite

      PURPOSE = "store and review notifications from operator-authorized apps".freeze
      PRIORITY = { mention: 75, message: 50, alert: 100, system: 25 }.freeze
      URGENT = /\b(?:urgent|asap|immediately|critical|emergency)\b/i.freeze
      LOW = /\b(?:fyi|no\s+action\s+needed|informational)\b/i.freeze
      STORE_NAME = File.join("notifications", "inbox.json")
      MAX_ROWS = 2_000
      MAX_STORE_BYTES = 4 * 1024 * 1024
      MAX_TEXT_BYTES = 4_000
      MAX_LIMIT = 200

      def initialize(root: MasterPaths.state, permission_check: nil, snooze_hours: 24,
                     clock: -> { Time.now.utc })
        @root = File.expand_path(root)
        @path = File.join(@root, STORE_NAME)
        @lock_path = "#{@path}.lock"
        @permission_check = permission_check || lambda {
          PersonalPermissions.new(root: Master::ROOT).allowed?(scope: "notifications", purpose: PURPOSE)
        }
        @snooze_hours = Float(snooze_hours)
        raise ArgumentError, "snooze_hours must be 1..720" unless @snooze_hours.finite? && @snooze_hours.between?(1, 720)
        @clock = clock
        FileUtils.mkdir_p(File.dirname(@path), mode: 0o700)
        File.chmod(0o700, File.dirname(@path))
      end

      def record(platform:, kind:, text:, timestamp: now)
        return denied unless permitted?
        body = text.to_s
        return Result.err("notification_aggregator: text is empty or too long", category: :validation) if body.strip.empty? || body.bytesize > MAX_TEXT_BYTES
        source = identifier(platform, "platform")
        type = identifier(kind, "kind")
        at = coerce_time(timestamp)
        row = {
          "id" => SecureRandom.hex(16), "platform" => source, "kind" => type,
          "text" => body, "timestamp" => at.iso8601,
          "priority" => priority_for(type, body), "status" => "UNREAD",
        }
        with_lock do
          data = load
          data["rows"] << row
          data["rows"] = data["rows"].last(MAX_ROWS)
          persist(data)
        end
        Result.ok(row)
      rescue ArgumentError => error
        Result.err("notification_aggregator: #{error.message}", category: :validation)
      rescue StandardError => error
        Result.err("notification_aggregator: #{error.class}: #{error.message}", category: :infrastructure)
      end

      def pending(limit: 100)
        return denied unless permitted?
        amount = Integer(limit)
        return Result.err("notification_aggregator: limit must be 1..#{MAX_LIMIT}", category: :validation) unless amount.between?(1, MAX_LIMIT)

        rows = with_lock do
          data = load
          changed = unsnooze(data)
          persist(data) if changed
          data.fetch("rows").select { |row| row["status"] == "UNREAD" }
        end
        ordered = rows.sort_by { |row| [-priority_number(row["priority"]), row["timestamp"]] }
        Result.ok(schema: 1, total: ordered.size, rows: ordered.first(amount))
      rescue ArgumentError => error
        Result.err("notification_aggregator: #{error.message}", category: :validation)
      rescue StandardError => error
        Result.err("notification_aggregator: #{error.class}: #{error.message}", category: :infrastructure)
      end

      def mark_read(id:)
        update(id, "status" => "READ")
      end

      def snooze(id:, hours: nil)
        amount = hours.nil? ? @snooze_hours : Float(hours)
        return Result.err("notification_aggregator: snooze hours must be 1..720", category: :validation) unless amount.finite? && amount.between?(1, 720)
        update(id, "status" => "SNOOZED", "until" => (now + amount * 3600).iso8601)
      rescue ArgumentError, TypeError => error
        Result.err("notification_aggregator: #{error.message}", category: :validation)
      end

      def status
        return denied unless permitted?
        with_lock do
          rows = load.fetch("rows")
          Result.ok(schema: 1, total: rows.size, unread: rows.count { |row| row["status"] == "UNREAD" })
        end
      rescue StandardError => error
        Result.err("notification_aggregator: #{error.class}: #{error.message}", category: :infrastructure)
      end

      private

      def permitted?
        @permission_check.call == true
      rescue StandardError
        false
      end

      def denied = Result.err("notification_aggregator: explicit notifications permission is required", category: :policy)

      def identifier(value, name)
        text = value.to_s.strip
        raise ArgumentError, "#{name} is invalid" unless text.match?(/\A[a-zA-Z0-9_.-]{1,40}\z/)
        text
      end

      def priority_for(kind, text)
        return "urgent" if text.match?(URGENT)
        return "low" if text.match?(LOW)

        number = PRIORITY.fetch(kind.to_sym, 50)
        return "urgent" if number >= 100
        return "high" if number >= 75
        return "medium" if number >= 50
        "low"
      end

      def priority_number(value)
        { "urgent" => 100, "high" => 75, "medium" => 50, "low" => 25 }.fetch(value, 0)
      end

      def update(id, changes)
        return denied unless permitted?
        with_lock do
          data = load
          row = data.fetch("rows").find { |entry| entry["id"] == id.to_s }
          return Result.err("notification_aggregator: no such id", category: :validation) unless row
          row.merge!(changes)
          persist(data)
          Result.ok(row)
        end
      rescue StandardError => error
        Result.err("notification_aggregator: #{error.class}: #{error.message}", category: :infrastructure)
      end

      def unsnooze(data)
        changed = false
        data.fetch("rows").each do |row|
          next unless row["status"] == "SNOOZED"
          deadline = Time.iso8601(row["until"].to_s)
          next if deadline > now
          row["status"] = "UNREAD"
          row.delete("until")
          changed = true
        rescue ArgumentError
          row["status"] = "UNREAD"
          row.delete("until")
          changed = true
        end
        changed
      end

      def coerce_time(value)
        time = value.is_a?(Time) ? value : Time.iso8601(value.to_s)
        time.utc
      rescue ArgumentError
        raise ArgumentError, "timestamp must be Time or ISO-8601"
      end

      def now
        value = @clock.call
        raise TypeError, "clock must return Time" unless value.is_a?(Time)
        value.utc
      end

      def with_lock
        File.open(@lock_path, File::RDWR | File::CREAT, 0o600) do |lock|
          lock.flock(File::LOCK_EX)
          yield
        ensure
          lock&.flock(File::LOCK_UN) rescue nil
        end
      end

      def load
        return { "schema" => 1, "rows" => [] } unless File.exist?(@path)
        raise IOError, "notification inbox must not be a symlink" if File.symlink?(@path)
        raise IOError, "notification inbox exceeds #{MAX_STORE_BYTES} bytes" if File.size(@path) > MAX_STORE_BYTES
        data = JSON.parse(File.read(@path, encoding: "UTF-8"))
        raise IOError, "notification inbox schema is invalid" unless data.is_a?(Hash) && data["schema"] == 1 && data["rows"].is_a?(Array)
        data
      rescue JSON::ParserError => error
        raise IOError, "notification inbox is corrupt: #{error.message.lines.first}"
      end

      def persist(data)
        write_atomic(@path, JSON.pretty_generate(data) + "\n", mode: 0o600)
      end
    end
  end
end
