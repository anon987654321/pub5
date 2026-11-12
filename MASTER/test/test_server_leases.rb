# frozen_string_literal: true

require_relative "test_helper"
require "rbconfig"
require "tmpdir"
require_relative "../lib/fix/server_leases"

# The servers a /fix run booted outlived it by hours when it was stopped: bin/master's traps end in
# exit!, and nothing reaped what a dead run left.
class TestServerLeases < Minitest::Test
  Leases = Master::Fix::ServerLeases

  def lease(run_dir, name, owner:, pid:)
    File.write(File.join(run_dir, "#{name}.pid"), "#{pid}\n")
    File.write(File.join(run_dir, "#{name}.pid.owner"), "#{owner} #{pid}\n")
  end

  def test_the_server_of_a_dead_owner_is_reaped
    Dir.mktmpdir("triangle-run") do |run_dir|
      lease(run_dir, "amber", owner: 111, pid: 61_352)
      killed = []

      reaped = Leases.reap_orphans!(run_dir, alive: ->(_owner) { false }, killer: ->(pid) { killed << pid; true })

      assert_equal ["amber"], reaped
      assert_equal [61_352], killed
      refute File.exist?(File.join(run_dir, "amber.pid"))
    end
  end

  def test_a_live_owners_server_and_a_stale_lease_are_not_killed
    Dir.mktmpdir("triangle-run") do |run_dir|
      lease(run_dir, "master", owner: 222, pid: 53_187)
      lease(run_dir, "bsdports", owner: 333, pid: 47_312)
      File.delete(File.join(run_dir, "bsdports.pid"))
      killed = []

      reaped = Leases.reap_orphans!(run_dir, alive: ->(owner) { owner == 222 }, killer: ->(pid) { killed << pid })

      assert_empty reaped
      assert_empty killed
      assert File.exist?(File.join(run_dir, "master.pid.owner")), "a live run's server is its own"
      refute File.exist?(File.join(run_dir, "bsdports.pid.owner")), "a stale lease is only removed"
    end
  end

  def test_an_unconfirmed_orphan_stop_keeps_both_files_for_retry
    Dir.mktmpdir("triangle-run") do |run_dir|
      pid_path = File.join(run_dir, "amber.pid")
      owner_path = "#{pid_path}.owner"
      lease(run_dir, "amber", owner: 111, pid: 61_352)

      first = Leases.reap_orphans!(
        run_dir, alive: ->(_owner) { false }, killer: ->(_pid) { false }
      )

      assert_empty first
      assert_equal "61352\n", File.read(pid_path)
      assert_equal "111 61352\n", File.read(owner_path)

      second = Leases.reap_orphans!(
        run_dir, alive: ->(_owner) { false }, killer: ->(_pid) { true }
      )

      assert_equal ["amber"], second
      refute File.exist?(pid_path)
      refute File.exist?(owner_path)
    end
  end

  def test_orphan_reaper_does_not_remove_a_replacement_owner_lease
    Dir.mktmpdir("triangle-run") do |run_dir|
      pid_path = File.join(run_dir, "amber.pid")
      owner_path = "#{pid_path}.owner"
      lease(run_dir, "amber", owner: 111, pid: 61_352)
      killer = lambda do |_pid|
        File.write(owner_path, "222 61352\n")
        true
      end

      assert_empty Leases.reap_orphans!(run_dir, alive: ->(_owner) { false }, killer:)
      assert_equal "222 61352\n", File.read(owner_path)
    end
  end

  def test_process_group_stop_escalates_and_waits_for_the_group_to_disappear
    Dir.mktmpdir("triangle-group-stop") do |dir|
      child_file = File.join(dir, "renderer.pid")
      child_code = "Signal.trap('TERM', 'IGNORE'); File.write(#{child_file.dump}, Process.pid.to_s); sleep 30"
      leader_code = <<~RUBY
        Signal.trap("TERM", "IGNORE")
        Process.spawn(RbConfig.ruby, "-e", #{child_code.dump}, out: File::NULL, err: File::NULL)
        sleep 30
      RUBY
      pid = Process.spawn(RbConfig.ruby, "-e", leader_code, pgroup: true, out: File::NULL, err: File::NULL)
      waiter = Process.detach(pid)
      child = wait_for_file(child_file).to_i

      assert_equal pid, Process.getpgid(child)
      assert Leases.stop_process_group(pid, term_grace: 0.1, kill_grace: 1.0)
      refute waiter.alive?
      assert_process_gone(child)
      refute Leases.process_group_alive?(pid)
    ensure
      if defined?(pid) && pid
        Process.kill("KILL", -pid) rescue nil
      end
      waiter&.join(1) if defined?(waiter)
    end
  end

  # The real trap context, where a Mutex cannot be taken and exit! follows at once.
  def test_a_term_trap_that_exits_bang_still_stops_the_held_server
    Dir.mktmpdir("trap-proof") do |dir|
      marker = File.join(dir, "stopped")
      status = term_child(trap_script(dir, marker))

      assert_equal 143, status.exitstatus
      assert_equal "61352", File.read(marker)
    end
  end

  def wait_for_file(path, timeout: 3)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    until File.file?(path)
      raise "subprocess did not publish #{File.basename(path)}" if
        Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

      sleep 0.01
    end
    File.read(path)
  end

  def assert_process_gone(pid)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 2
    loop do
      begin
        Process.kill(0, pid)
      rescue Errno::ESRCH
        return
      end
      flunk "child process #{pid} survived process-group stop" if
        Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

      sleep 0.01
    end
  end

  def term_child(script)
    IO.popen([RbConfig.ruby, "-e", script], err: File::NULL) do |child|
      assert_equal "ready\n", child.gets

      Process.kill("TERM", child.pid)
      Process.wait2(child.pid).last
    end
  end

  def trap_script(dir, marker)
    <<~RUBY
      require #{File.expand_path("../lib/fix/server_leases", __dir__).inspect}

      lease = Object.new
      lease.define_singleton_method(:stop_owned!) { File.write(#{marker.inspect}, "61352") }
      Master::Fix::ServerLeases.hold(lease, pid_path: #{File.join(dir, "amber.pid").inspect}, pid: 61_352)
      trap("TERM") { Master::Fix::ServerLeases.stop_all_from_trap!; exit!(143) }
      $stdout.puts "ready"
      $stdout.flush
      sleep 30
    RUBY
  end
end
