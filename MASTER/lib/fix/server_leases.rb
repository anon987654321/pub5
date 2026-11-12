# frozen_string_literal: true

require "fileutils"

module Master
  module Fix
    # The app servers this process booted and owns. bin/master's TERM and INT traps end in exit!, which
    # runs no ensure and no at_exit, so a /fix run stopped mid-pass left its apps serving for hours (an
    # amber puma for five, a master server for six). The traps and an at_exit hook stop the leases held
    # here; a lease file beside each pid file names the owning process, so the wrapper that outlives a
    # run can stop the servers of one that died past both. A lease already released stops nothing, so
    # one is never dropped from the list: stop_owned! on it answers [] at once.
    module ServerLeases
      OWNER_SUFFIX = ".owner"
      TERM_GRACE_S = 2.0
      KILL_GRACE_S = 2.0
      STOP_POLL_S = 0.05

      @held = []

      module_function

      # A lease (anything answering stop_owned!) that now owns the server whose pid sits in pid_path.
      def hold(lease, pid_path:, pid:)
        File.write("#{pid_path}#{OWNER_SUFFIX}", "#{Process.pid} #{pid}\n")
        @held << lease unless @held.include?(lease)
        @exit_hook ||= at_exit { stop_all! }
      end

      # Remove only this process's exact ownership record. A changed PID is a
      # different server and must never inherit the old run's lease.
      def release(pid_path:, pid:, owner: Process.pid)
        owner_path = "#{pid_path}#{OWNER_SUFFIX}"
        return false unless File.file?(owner_path)

        owner_pid, server_pid = File.read(owner_path).split.map(&:to_i)
        return false unless owner_pid == owner.to_i && server_pid == pid.to_i

        FileUtils.rm_f(owner_path)
        true
      rescue StandardError
        false
      end

      def held = @held.dup

      def stop_all!
        held.each(&:stop_owned!)
      end

      # Callable from a signal trap, where a Mutex cannot be taken: the stop runs on its own thread.
      def stop_all_from_trap!(wait_s: 10)
        Thread.new { stop_all! }.join(wait_s)
      end

      # A stopped group is a proved stop. TERM is given a bounded grace period;
      # KILL is sent only to the process group the launcher created for this app.
      # A false result keeps both the PID file and owner lease for a later retry.
      def stop_process_group(pid, term_grace: TERM_GRACE_S, kill_grace: KILL_GRACE_S)
        group = Integer(pid)
        return false unless group.positive?

        signal_group("TERM", group)
        return true if wait_for_group_exit(group, term_grace)

        signal_group("KILL", group)
        wait_for_group_exit(group, kill_grace)
      rescue ArgumentError, TypeError
        false
      end

      def wait_for_group_exit(group, timeout)
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
        loop do
          return true unless process_group_alive?(group)
          return false if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

          sleep STOP_POLL_S
        end
      end

      def process_group_alive?(group)
        Process.kill(0, -group)
        true
      rescue Errno::ESRCH
        false
      rescue Errno::EPERM
        true
      end

      def signal_group(signal, group)
        Process.kill(signal, -group)
        true
      rescue Errno::ESRCH, Errno::EPERM
        false
      end

      # The servers whose owning process is gone, stopped; returns their app names. A lease whose pid
      # file is gone or names another pid is stale and only removed: that server is not the dead run's.
      def reap_orphans!(run_dir, alive: method(:alive?), killer: method(:stop_process_group))
        Dir.glob(File.join(run_dir, "*.pid#{OWNER_SUFFIX}")).filter_map do |lease|
          owner, pid = File.read(lease).split.map(&:to_i)
          next if alive.call(owner)

          reap(lease, pid:, killer:)
        end
      end

      def reap(lease, pid:, killer:)
        pid_path = lease.delete_suffix(OWNER_SUFFIX)
        unless File.file?(pid_path) && File.read(pid_path).to_i == pid
          FileUtils.rm_f(lease)
          return
        end

        stopped = stop_server(pid_path, pid:, killer:)
        return unless stopped

        FileUtils.rm_f(lease)
        File.basename(pid_path, ".pid")
      end

      def stop_server(pid_path, pid:, killer:)
        stopped = killer.call(pid)
        return false unless stopped == true || stopped == :already_gone

        FileUtils.rm_f(pid_path) if File.file?(pid_path) && File.read(pid_path).to_i == pid
        true
      rescue Errno::ESRCH
        FileUtils.rm_f(pid_path) if File.file?(pid_path) && File.read(pid_path).to_i == pid
        true
      end

      def alive?(pid)
        return false unless pid.positive?

        Process.kill(0, pid)
        true
      rescue Errno::ESRCH
        false
      rescue Errno::EPERM
        true
      end
    end
  end
end
