# frozen_string_literal: true

require "etc"
require "fileutils"
require "json"
require "securerandom"
require "socket"
require "time"
require_relative "deploy_inventory"

module Deploy
  # Durable deploy evidence only. This is deliberately not a command broker:
  # callers already hold the authority they need and invoke these data methods
  # directly. The state is root-owned and readable by wheel/dev for diagnosis.
  class Records
    ROOT = "/var/db/pub5"
    RUNS = "deploy_runs"
    STATUSES = %w[running ok failed recovered].freeze
    RECOVERY_STATES = %w[none pending complete].freeze
    RUN_ID = /\A\d{8}T\d{6}Z-[a-z0-9_-]{1,32}-\d+\z/
    TIMESTAMP = /\A\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ\z/
    LOG_PATH = /\A\/[A-Za-z0-9_.\/-]{1,2048}\z/

    def initialize(root: ROOT, repo_root: File.expand_path("../..", __dir__))
      @root = File.expand_path(root)
      inventory = Inventory.new(root: repo_root)
      @apps = inventory.app_names.freeze
      @services = @apps.flat_map do |app|
        service_file = "/etc/rc.d/#{app}_jobs"
        File.file?(service_file) ? [app, "#{app}_jobs"] : [app]
      end.freeze
    end

    def write(run_id, payload_json)
      raise ArgumentError, "invalid deploy-run ID" unless run_id?(run_id)

      payload = JSON.parse(payload_json)
      raise ArgumentError, "deploy-run update must be an object" unless payload.is_a?(Hash)
      unknown = payload.keys - allowed_fields
      raise ArgumentError, "unknown deploy-run field(s): #{unknown.join(', ')}" unless unknown.empty?

      previous = read(run_id)
      record = previous ? merge_update(payload, previous) : create_record(payload, run_id)
      record["updated_at"] = Time.now.utc.iso8601
      validate!(record, run_id)
      directory = directory!(create: true)
      target = File.join(directory, "#{run_id}.json")
      raise "#{target} is a symlink" if File.symlink?(target)
      if File.exist?(target)
        stat = File.lstat(target)
        raise "#{target} is not a root-owned regular file" unless stat.file? && !stat.symlink? && stat.uid.zero?
      end

      temporary = File.join(directory, ".#{run_id}.#{Process.pid}.#{SecureRandom.hex(6)}")
      begin
        File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
          file.write(JSON.generate(record) + "\n")
          file.flush
          file.fsync
        end
        File.chown(0, wheel_gid, temporary)
        File.chmod(0o640, temporary)
        File.rename(temporary, target)
        File.open(directory) { |dir| dir.fsync }
      ensure
        File.unlink(temporary) if File.exist?(temporary)
      end
      puts "deploy_run0: #{run_id} status=#{record.fetch('status')} recovery=#{record.fetch('recovery_state')} stage=#{record.fetch('stage')}"
      record
    end

    def read(run_id)
      raise ArgumentError, "invalid deploy-run ID" unless run_id?(run_id)
      directory = directory!(create: false)
      return nil unless directory

      path = File.join(directory, "#{run_id}.json")
      raise "#{path} is a symlink" if File.symlink?(path)
      return nil unless File.exist?(path)

      stat = File.lstat(path)
      raise "#{path} must be root-owned, wheel-readable regular file" unless
        stat.file? && !stat.symlink? && stat.uid.zero? && (stat.mode & 0o007).zero?
      record = JSON.parse(File.read(path))
      validate!(record, run_id)
    rescue JSON::ParserError
      raise "#{path} contains malformed deploy-run JSON"
    end

    def all
      directory = directory!(create: false)
      return [] unless directory

      names = Dir.children(directory).grep(/\A\d{8}T\d{6}Z-[a-z0-9_-]{1,32}-\d+\.json\z/).sort.reverse
      names.filter_map { |name| read(name.delete_suffix(".json")) }
    end

    def pending(max_scan: 500, max_pending: 100)
      raise ArgumentError, "invalid scan limit" unless max_scan.is_a?(Integer) && max_scan.positive?
      raise ArgumentError, "invalid pending limit" unless max_pending.is_a?(Integer) && max_pending.positive?

      directory = directory!(create: false)
      return { pending: [], truncated: false, scanned: 0, returned: 0 } unless directory

      names = []
      scanned = 0
      Dir.each_child(directory) do |name|
        next unless name.match?(/\A\d{8}T\d{6}Z-[a-z0-9_-]{1,32}-\d+\.json\z/)
        scanned += 1
        names << name
      end
      names.sort!.reverse!
      truncated = scanned > max_scan
      records = names.first(max_scan).filter_map do |name|
        read(name.delete_suffix(".json"))
      end.select do |record|
        record["recovery_state"] == "pending" && %w[running failed].include?(record["status"])
      end
      truncated ||= records.length > max_pending
      records = records.first(max_pending)
      { pending: records, truncated: truncated, scanned: scanned, returned: records.length }
    end

    def write_stamp(app, sha, status)
      raise ArgumentError, "unknown app" unless @apps.include?(app)
      raise ArgumentError, "invalid SHA" unless sha == "unknown" || sha.match?(/\A[0-9a-f]{7,40}\z/i)
      raise ArgumentError, "invalid stamp status" unless %w[ok failed ci_ok ci_attested ci_skipped].include?(status)

      ensure_root!
      target = File.join(@root, "last_deploy_#{app}.json")
      raise "#{target} is a symlink" if File.symlink?(target)
      payload = { app: app, sha: sha, at: Time.now.utc.iso8601, status: status, host: Socket.gethostname }
      write_json_atomically(target, payload, "stamp")
    end

    private

    def allowed_fields
      %w[schema run_id target host pid owner_identity status recovery_state stage
         started_at updated_at pinned_sha previous_sha started_services ports restore_order
         run_log aggregate_log recovered_at snapshot_recorded]
    end

    def run_id?(value) = value.is_a?(String) && RUN_ID.match?(value)

    def wheel_gid = Etc.getgrnam("wheel").gid

    def ensure_root!
      parent = File.dirname(@root)
      raise "#{parent} must be a real directory" unless File.directory?(parent) && !File.symlink?(parent)
      raise "#{@root} is a symlink" if File.symlink?(@root)
      FileUtils.mkdir_p(@root, mode: 0o755)
      stat = File.lstat(@root)
      raise "#{@root} must be a root-owned directory" unless stat.directory? && stat.uid.zero?
      File.chown(0, wheel_gid, @root)
      File.chmod(0o755, @root)
    end

    def directory!(create:)
      ensure_root! if create
      return unless File.exist?(@root)
      stat = File.lstat(@root)
      raise "#{@root} must be a real root-owned directory" unless stat.directory? && !stat.symlink? && stat.uid.zero?

      path = File.join(@root, RUNS)
      raise "#{path} is a symlink" if File.symlink?(path)
      if !File.exist?(path)
        return unless create
        Dir.mkdir(path, 0o750)
        File.chown(0, wheel_gid, path)
      end
      dir = File.lstat(path)
      raise "#{path} must be a real root-owned directory" unless dir.directory? && !dir.symlink? && dir.uid.zero?
      File.chown(0, wheel_gid, path)
      File.chmod(0o750, path)
      if create
        Dir.each_child(path) do |name|
          next unless name.match?(/\\A\\d{8}T\\d{6}Z-[a-z0-9_-]{1,32}-\\d+\\.json\\z/)
          entry = File.join(path, name)
          raise "#{entry} is a symlink" if File.symlink?(entry)
          stat = File.lstat(entry)
          raise "#{entry} must be a root-owned regular file" unless stat.file? && stat.uid.zero?
          File.chown(0, wheel_gid, entry)
          File.chmod(0o640, entry)
        end
      end
      path
    end

    def create_record(payload, run_id)
      required = %w[schema run_id target host pid owner_identity status recovery_state stage started_at
                    started_services ports restore_order run_log aggregate_log snapshot_recorded]
      missing = required - payload.keys
      raise ArgumentError, "deploy-run creation missing #{missing.join(', ')}" unless missing.empty?
      raise ArgumentError, "deploy-run ID mismatch" unless payload["run_id"] == run_id
      payload
    end

    def merge_update(payload, previous)
      terminal = %w[ok recovered].include?(previous["status"]) ||
                 (previous["status"] == "failed" && previous["recovery_state"] != "pending")
      raise ArgumentError, "terminal deploy-run receipt cannot be changed" if terminal

      %w[schema run_id target host pid owner_identity started_at run_log aggregate_log].each do |field|
        next unless payload.key?(field)
        raise ArgumentError, "deploy-run identity #{field} cannot change" unless payload[field] == previous[field]
      end
      if previous["snapshot_recorded"]
        %w[pinned_sha previous_sha started_services ports restore_order].each do |field|
          next unless payload.key?(field)
          raise ArgumentError, "deploy-run snapshot #{field} cannot change" unless payload[field] == previous[field]
        end
        raise ArgumentError, "deploy-run snapshot marker cannot be cleared" if payload["snapshot_recorded"] == false
      end
      previous.merge(payload)
    end

    def validate!(record, run_id)
      raise ArgumentError, "invalid deploy-run record" unless record.is_a?(Hash)
      raise ArgumentError, "invalid schema or ID" unless record["schema"] == 1 && record["run_id"] == run_id
      raise ArgumentError, "invalid target" unless record["target"].is_a?(String) && (@apps + %w[all rails]).include?(record["target"])
      raise ArgumentError, "invalid host" unless record["host"].is_a?(String) && record["host"].bytesize.between?(1, 255) && !record["host"].match?(/[\x00-\x1f]/)
      raise ArgumentError, "invalid PID" unless record["pid"].is_a?(Integer) && record["pid"].positive?
      raise ArgumentError, "invalid owner identity" unless record["owner_identity"].is_a?(String) && record["owner_identity"].match?(/\A[A-Za-z0-9_]{1,220}\z/)
      raise ArgumentError, "invalid status" unless STATUSES.include?(record["status"])
      raise ArgumentError, "invalid recovery state" unless RECOVERY_STATES.include?(record["recovery_state"])
      raise ArgumentError, "invalid stage" unless record["stage"].is_a?(String) && record["stage"].bytesize.between?(1, 160) && record["stage"].match?(/\A[A-Za-z0-9_.:+\/-]+\z/)
      raise ArgumentError, "invalid snapshot marker" unless [true, false].include?(record["snapshot_recorded"])
      %w[started_at updated_at].each do |field|
        value = record[field]
        raise ArgumentError, "invalid #{field}" unless value.is_a?(String) && TIMESTAMP.match?(value)
        Time.iso8601(value)
      end
      %w[pinned_sha previous_sha].each do |field|
        value = record[field]
        valid = value.nil? || value == "unknown" || (value.is_a?(String) && value.match?(/\A[0-9a-f]{7,40}\z/i))
        raise ArgumentError, "invalid #{field}" unless valid
      end
      services = record["started_services"]
      raise ArgumentError, "invalid service snapshot" unless services.is_a?(Array) && services.length <= @services.length && services.uniq == services && services.all? { |name| @services.include?(name) }
      ports = record["ports"]
      raise ArgumentError, "invalid port map" unless ports.is_a?(Hash) && ports.all? { |name, port| @apps.include?(name) && port.is_a?(Integer) && (1..65_535).cover?(port) }
      order = record["restore_order"]
      raise ArgumentError, "invalid restore order" unless order.is_a?(Array) && order.length <= @apps.length && order.uniq == order && order.all? { |name| @apps.include?(name) }
      %w[run_log aggregate_log].each do |field|
        value = record[field]
        raise ArgumentError, "invalid #{field}" unless value.is_a?(String) && value.bytesize.between?(1, 2048) && LOG_PATH.match?(value)
      end
      if record.key?("recovered_at")
        value = record["recovered_at"]
        raise ArgumentError, "invalid recovered_at" unless value.is_a?(String) && TIMESTAMP.match?(value)
        Time.iso8601(value)
      end
      record
    rescue ArgumentError => error
      raise error if error.message.start_with?("invalid", "terminal", "deploy-run")
      raise ArgumentError, "invalid deploy-run timestamp"
    end

    def write_json_atomically(target, payload, label)
      temporary = File.join(File.dirname(target), ".#{File.basename(target)}.#{Process.pid}.#{SecureRandom.hex(6)}")
      begin
        File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
          file.write(JSON.generate(payload) + "\n")
          file.flush
          file.fsync
        end
        File.chown(0, wheel_gid, temporary)
        File.chmod(0o640, temporary)
        File.rename(temporary, target)
        File.open(File.dirname(target)) { |dir| dir.fsync }
      ensure
        File.unlink(temporary) if File.exist?(temporary)
      end
      puts "#{label}0: #{target}"
    end
  end
end
