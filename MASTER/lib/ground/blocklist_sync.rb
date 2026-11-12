# frozen_string_literal: true

require "fileutils"
require "json"
require "time"
require_relative "../result"
require_relative "../io/atomic_write"
require_relative "../boot/paths"

module Master
  module Ground
    # Per-platform block propagation. A target is considered blocked only on
    # platforms whose API write returned a successful Result. No punishment is
    # issued here: the caller must provide an authorization decision per action.
    class BlocklistSync
      include ::Master::Io::AtomicWrite

      STORE_NAME = File.join("blocklist_sync", "blocks.json")
      TARGET_TYPES = %w[user account profile].freeze
      MAX_PLATFORMS = 12
      MAX_REASON_BYTES = 500
      MAX_BLOCKS = 10_000
      MAX_STORE_BYTES = 4 * 1024 * 1024

      def initialize(rails_clients: {}, root: MasterPaths.state, authorize: nil, unblocker: nil,
                     clock: -> { Time.now.utc })
        @clients = rails_clients.to_h.transform_keys(&:to_s)
        @root = File.expand_path(root)
        @path = File.join(@root, STORE_NAME)
        @lock_path = "#{@path}.lock"
        @authorize = authorize || ->(**) { false }
        @unblocker = unblocker
        @clock = clock
        FileUtils.mkdir_p(File.dirname(@path), mode: 0o700)
        File.chmod(0o700, File.dirname(@path))
        @data = load
      end

      def block(target_id:, target_type: :user, reason:, platforms:, permanent: true, ttl_s: nil)
        id = required_text(target_id, "target_id", 200)
        type = target_type.to_s
        raise ArgumentError, "unsupported target_type" unless TARGET_TYPES.include?(type)
        detail = required_text(reason, "reason", MAX_REASON_BYTES)
        names = Array(platforms).map(&:to_s).uniq
        raise ArgumentError, "platforms must be a non-empty bounded list" if names.empty? || names.size > MAX_PLATFORMS
        unknown = names - @clients.keys
        raise ArgumentError, "unknown platform(s): #{unknown.join(', ')}" unless unknown.empty?

        ttl = normalize_ttl(permanent, ttl_s)

        entry = {
          "target_id" => id, "target_type" => type, "reason" => detail,
          "created_at" => now.iso8601, "expires_at" => ttl && (now + ttl).iso8601,
          "platform_status" => {},
        }
        with_lock do
          @data = load
          previous = @data["blocks"].find { |row| row["target_id"] == id }
          raise IOError, "block list reached its record limit" if previous.nil? && @data["blocks"].size >= MAX_BLOCKS
          sync_platforms = (names + previous.to_h.fetch("platform_status", {}).keys).uniq
          return Result.err("blocklist_sync: explicit authorization is required", category: :policy) unless
            authorized?(:block, id, sync_platforms)
          entry["platform_status"] = sync_platforms.to_h { |platform| [platform, "PENDING"] }
          @data["blocks"].reject! { |row| row["target_id"] == id }
          @data["blocks"] << entry
          persist
        end
        entry["platform_status"].keys.each do |platform|
          client = @clients[platform]
          unless client
            entry["platform_status"][platform] = "UNKNOWN"
            next
          end
          begin
            response = client.post(
              "/api/blocks",
              body: { target_id: id, target_type: type, reason: detail,
                      permanent: permanent == true, ttl_s: ttl },
            )
            entry["platform_status"][platform] = response.ok? ? "SYNCED" : "FAILED"
          rescue StandardError
            entry["platform_status"][platform] = "FAILED"
          end
        end
        with_lock do
          @data = load
          current = @data["blocks"].find { |row| row["target_id"] == id }
          current["platform_status"].merge!(entry["platform_status"]) if current
          persist
        end

        failures = entry["platform_status"].select { |_platform, status| status != "SYNCED" }.keys
        return Result.err("blocklist_sync: some platforms did not confirm the write",
                          category: :infrastructure, context: { failed_platforms: failures }) unless failures.empty?

        Result.ok(entry)
      rescue ArgumentError => error
        Result.err("blocklist_sync: #{error.message}", category: :validation)
      rescue StandardError => error
        Result.err("blocklist_sync: #{error.class}: #{error.message}", category: :infrastructure)
      end

      # A local record is not erased until each remote adapter confirms the
      # unblock. MASTER deliberately supplies no default route guess.
      def unblock(target_id:)
        id = required_text(target_id, "target_id", 200)
        return Result.err("blocklist_sync: no verified remote unblock adapter is configured", category: :policy) unless @unblocker

        entry = with_lock do
          load.fetch("blocks").find { |row| row["target_id"] == id }
        end
        return Result.err("blocklist_sync: no such block", category: :validation) unless entry
        platforms = entry.fetch("platform_status", {}).select { |_name, status| status == "SYNCED" }.keys
        return Result.err("blocklist_sync: explicit authorization is required", category: :policy) unless authorized?(:unblock, id, platforms)

        outcomes = {}
        platforms.each do |platform|
          result = @unblocker.call(client: @clients.fetch(platform), platform:, target_id: id)
          outcomes[platform] = result.respond_to?(:ok?) && result.ok? ? "UNBLOCKED" : "SYNCED"
        rescue StandardError
          outcomes[platform] = "FAILED"
        end
        failures = outcomes.select { |_platform, status| status != "UNBLOCKED" }.keys
        with_lock do
          @data = load
          current = @data["blocks"].find { |row| row["target_id"] == id }
          if current
            outcomes.each { |platform, status| current["platform_status"][platform] = status }
            @data["blocks"].reject! do |row|
              row["target_id"] == id && row.fetch("platform_status", {}).values.none? { |status| status == "SYNCED" }
            end
            persist
          end
        end
        return Result.err("blocklist_sync: some remote blocks remain", category: :infrastructure,
                          context: { failed_platforms: failures }) unless failures.empty?

        Result.ok(removed: true, target_id: id, remote_sync: "CONFIRMED")
      rescue ArgumentError => error
        Result.err("blocklist_sync: #{error.message}", category: :validation)
      rescue StandardError => error
        Result.err("blocklist_sync: #{error.class}: #{error.message}", category: :infrastructure)
      end

      def blocked?(target_id:, platform:)
        entry = with_lock { load.fetch("blocks").find { |row| row["target_id"] == target_id.to_s } }
        return false unless entry
        return false unless entry.fetch("platform_status", {})[platform.to_s] == "SYNCED"
        return false if entry["expires_at"] && Time.iso8601(entry["expires_at"]) <= now

        true
      rescue ArgumentError
        false
      end

      def status
        with_lock do
          rows = load.fetch("blocks")
          Result.ok(
            schema: 1, blocks: rows.size,
            platforms: rows.flat_map { |row| row.fetch("platform_status", {}).keys }.uniq.sort,
            confirmed_syncs: rows.sum { |row| row.fetch("platform_status", {}).values.count("SYNCED") },
          )
        end
      end

      private

      def required_text(value, name, bytes)
        text = value.to_s.strip
        raise ArgumentError, "#{name} is required" if text.empty?
        raise ArgumentError, "#{name} is too long" if text.bytesize > bytes
        text
      end

      def normalize_ttl(permanent, ttl_s)
        return nil if permanent == true
        value = Integer(ttl_s)
        raise ArgumentError, "ttl_s must be 60..31536000 for temporary blocks" unless value.between?(60, 31_536_000)
        value
      rescue TypeError, ArgumentError
        raise ArgumentError, "temporary blocks require ttl_s between 60 and 31536000"
      end

      def authorized?(action, target_id, platforms)
        @authorize.call(action:, target_id:, platforms:) == true
      rescue StandardError
        false
      end

      def now
        value = @clock.call
        raise TypeError, "clock must return Time" unless value.is_a?(Time)
        value.utc
      end

      def load
        return { "schema" => 1, "blocks" => [] } unless File.exist?(@path)
        raise IOError, "block list path must not be a symlink" if File.symlink?(@path)
        raise IOError, "block list ledger exceeds its size limit" if File.size(@path) > MAX_STORE_BYTES
        parsed = JSON.parse(File.read(@path, encoding: "UTF-8"))
        raise IOError, "block list schema is invalid" unless parsed.is_a?(Hash) && parsed["schema"] == 1 && parsed["blocks"].is_a?(Array)
        parsed
      rescue JSON::ParserError => error
        raise IOError, "block list ledger is corrupt: #{error.message.lines.first}"
      end

      def with_lock
        File.open(@lock_path, File::RDWR | File::CREAT, 0o600) do |lock|
          lock.flock(File::LOCK_EX)
          yield
        ensure
          lock&.flock(File::LOCK_UN) rescue nil
        end
      end

      def persist
        content = JSON.pretty_generate(@data) + "\n"
        raise IOError, "block list ledger would exceed its size limit" if content.bytesize > MAX_STORE_BYTES
        write_atomic(@path, content, mode: 0o600)
      end
    end
  end
end
