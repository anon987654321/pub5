# frozen_string_literal: true

require "fileutils"
require "rbconfig"
require "socket"
require_relative "server_leases"

module Master
  module Fix
    # Owns the local Rails-server lease for one /fix run. Reuses the canonical
    # Triangle launcher and its RAILS/apps.yml ports; never takes ownership of
    # servers that were already serving before this run.
    class VisualRuntime
      Result = Data.define(:ok, :message, :started, :already_running) do
        def ok? = ok
      end

      attr_reader :started

      def initialize(root:, bus: nil, triangle: nil, database_url: ENV["DATABASE_URL"],
                     host_os: RbConfig::CONFIG["host_os"], tcp_checker: nil, killer: nil)
        expanded = File.expand_path(root)
        @root = File.basename(expanded) == "MASTER" ? File.expand_path("..", expanded) : expanded
        @bus = bus
        @triangle = triangle
        @database_url = database_url
        @host_os = host_os.to_s
        @tcp_checker = tcp_checker || method(:tcp_open?)
        @killer = killer || method(:kill_process_group)
        @owned = {}
        @started = []
      end

      # Returns a Result instead of silently turning a server failure into a
      # clean render. Only missing app servers are started; existing servers are
      # left alone and are never stopped by this lease.
      def ensure_running!(names)
        names = Array(names).map(&:to_s).uniq
        return success("no visual app servers requested", []) if names.empty?

        manager = triangle
        apps = requested_apps(manager, names)
        return apps if apps.is_a?(Result)
        already_running = apps.select { |app| manager.listening?(app.fetch(:port)) }
        missing = apps - already_running
        return success("visual app servers already running", already_running.map { |app| app[:name] }) if missing.empty?

        return failure(unsafe_boot_message) if unsafe_boot_message
        return failure(occupied_port_message(missing)) if occupied_port_message(missing)

        failed = start_missing(manager:, missing:, names:)
        return failed if failed.is_a?(Result)

        publish(:ready, apps: names, started: @started.dup, already_running: already_running.map { |app| app[:name] })
        success("visual app servers ready", already_running.map { |app| app[:name] })
      rescue StandardError => e
        detail = "#{e.class}: #{e.message}"
        publish(:inconclusive, apps: names, started: @started.dup, reason: detail)
        failure("visual app-server bridge failed: #{detail}")
      end

      # Called once at /fix termination (not after every visual pass). The
      # screenshot directory may be deleted per pass while servers stay warm for
      # the next measure/repair/remeasure cycle.
      def stop_owned!
        return [] if @owned.empty?

        stopped = []
        remaining = {}
        @owned.each do |name, lease|
          current = read_pid(lease[:pid_path])
          unless current == lease[:pid]
            ServerLeases.release(pid_path: lease[:pid_path], pid: lease[:pid])
            next
          end

          confirmed = @killer.call(current)
          unless confirmed == true || confirmed == :already_gone
            remaining[name] = lease
            Master::Trace::Dmesg.status("fix0", "kept #{name} server lease; process-group exit is unconfirmed (pid #{current})")
            next
          end

          FileUtils.rm_f(lease[:pid_path]) if read_pid(lease[:pid_path]) == current
          ServerLeases.release(pid_path: lease[:pid_path], pid: current)
          stopped << name
        rescue Errno::ESRCH
          FileUtils.rm_f(lease[:pid_path]) if read_pid(lease[:pid_path]) == lease[:pid]
          ServerLeases.release(pid_path: lease[:pid_path], pid: lease[:pid])
          stopped << name
        rescue StandardError => e
          remaining[name] = lease
          Master::Ground::Swallow.log(e, context: "fix.visual_runtime.stop", event_bus: @bus, app: name, pid: lease[:pid])
        end
        @owned = remaining
        publish(:released, stopped:) if stopped.any?
        stopped
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "fix.visual_runtime.stop", event_bus: @bus)
        []
      end

      private

      def requested_apps(manager, names)
        indexed = manager.apps.to_h { |app| [app.fetch(:name).to_s, app] }
        unknown = names - indexed.keys
        return failure("unknown visual app server(s): #{unknown.join(', ')}") if unknown.any?

        names.map { |name| indexed.fetch(name) }
      end

      def unsafe_boot_message
        reason = unsafe_boot_reason
        "visual server startup refused: #{reason}; rendered evidence is INCONCLUSIVE" if reason
      end

      def occupied_port_message(missing)
        occupied = missing.select { |app| @tcp_checker.call(app.fetch(:port)) }
        return if occupied.empty?

        labels = occupied.map { |app| "#{app[:name]}:#{app[:port]}" }
        "port accepts TCP but /up is not healthy (#{labels.join(', ')}); refusing to boot over an unknown process"
      end

      def start_missing(manager:, missing:, names:)
        prior = missing.to_h { |app| [app[:name].to_s, read_pid(manager.pid_file(app))] }
        wanted = missing.map { |app| app.fetch(:name).to_s }
        failed = manager.up(wanted) { |event| publish(:startup, apps: names, **event) }
        register_owned(manager:, missing:, prior:)
        unhealthy = missing.reject { |app| manager.listening?(app.fetch(:port)) }
        return unless failed.any? || unhealthy.any?

        failed_start(names:, failed:, unhealthy:)
      end

      def register_owned(manager:, missing:, prior:)
        missing.each do |app|
          name = app.fetch(:name).to_s
          pid_path = manager.pid_file(app)
          pid = read_pid(pid_path)
          next unless pid && pid != prior[name]

          @owned[name] = { app:, pid:, pid_path: }
          ServerLeases.hold(self, pid_path:, pid:)
          @started << name unless @started.include?(name)
        end
      end

      def failed_start(names:, failed:, unhealthy:)
        broken = (Array(failed).map(&:to_s) + unhealthy.map { |app| app[:name].to_s }).uniq
        detail = "could not start healthy app server(s): #{broken.join(', ')}"
        publish(:inconclusive, apps: names, started: @started.dup, reason: detail)
        failure(detail)
      end

      def triangle
        return @triangle if @triangle

        path = File.join(@root, "MASTER", "tools", "rails", "triangle.rb")
        raise "canonical Rails launcher is missing: #{path}" unless File.file?(path)

        # triangle.rb is also a CLI entrypoint. Its guard makes requiring the
        # canonical implementation safe; no second server launcher is created.
        require path
        @triangle = Deploy::Triangle
      end

      def unsafe_boot_reason
        return "DATABASE_URL is set; automatic db:prepare may target a non-local database" unless @database_url.to_s.empty?
        return "this is an OpenBSD host" if @host_os.match?(/openbsd/i)
        return "this is the production deployment checkout" if File.directory?("/home/dev/pub5") || @root == "/home/dev/pub5"

        nil
      end

      def tcp_open?(port)
        Socket.tcp("127.0.0.1", Integer(port), connect_timeout: 0.4) { true }
      rescue SystemCallError, IOError, ArgumentError
        false
      end

      def read_pid(path)
        return unless File.file?(path)

        value = Integer(File.read(path).strip, 10)
        value.positive? ? value : nil
      rescue ArgumentError, SystemCallError
        nil
      end

      def kill_process_group(pid)
        ServerLeases.stop_process_group(Integer(pid))
      end

      def success(message, already_running)
        Result.new(ok: true, message:, started: @started.dup, already_running: Array(already_running))
      end

      def failure(message)
        Result.new(ok: false, message:, started: @started.dup, already_running: [])
      end

      def publish(state, **payload)
        @bus&.publish("fix:visual_runtime", state:, **payload)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "fix.visual_runtime.event", event_bus: @bus)
      end
    end
  end
end
