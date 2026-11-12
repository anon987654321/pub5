# frozen_string_literal: true

require_relative "test_helper"
require "rbconfig"
require "tmpdir"
require_relative "../checks/support/chrome_process"
require_relative "../checks/support/cdp_session"

class TestChromeProcessSupervision < Minitest::Test
  class Reaper
    include Deploy::ChromeProcess

    attr_accessor :pid

    def initialize(pid)
      @pid = pid
    end

    def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    def chrome_term_grace = 0.15
    def chrome_kill_grace = 1.0
    def chrome_stop_poll = 0.01
  end

  def test_reaper_kills_the_isolated_chrome_group_and_reaps_its_leader
    Dir.mktmpdir("chrome-reaper") do |dir|
      leader_file = File.join(dir, "leader.pid")
      child_file = File.join(dir, "renderer.pid")
      child_script = <<~'RUBY'
        Signal.trap("TERM", "IGNORE")
        File.write(ARGV.fetch(0), Process.pid.to_s)
        sleep 60
      RUBY
      leader_script = <<~'RUBY'
        Process.spawn(
          RbConfig.ruby, "-e", ARGV.fetch(2), ARGV.fetch(1),
          out: File::NULL, err: File::NULL
        )
        File.write(ARGV.fetch(0), Process.pid.to_s)
        sleep 60
      RUBY
      leader = Process.spawn(
        RbConfig.ruby, "-e", leader_script, leader_file, child_file, child_script,
        out: File::NULL, err: File::NULL, pgroup: true
      )
      child = wait_for_file(child_file).to_i
      assert_equal leader, File.read(leader_file).to_i
      assert_equal leader, Process.getpgid(leader)
      assert_equal leader, Process.getpgid(child), "renderer must remain inside the owned browser group"

      reaper = Reaper.new(leader)
      assert reaper.reap_chrome, "teardown must prove group exit and direct-child reap"
      assert_nil reaper.pid
      assert_process_gone(leader)
      assert_process_gone(child)
    ensure
      if defined?(leader) && leader
        Process.kill("KILL", -leader) rescue nil
        Process.waitpid(leader) rescue nil
      end
    end
  end

  def test_inconclusive_group_shutdown_retains_the_pid_for_a_retry
    reaper = Reaper.new(987_654_321)
    reaper.define_singleton_method(:signal_chrome_group) { |_signal, _pid| false }
    reaper.define_singleton_method(:reap_chrome_leader) { |_pid| true }
    reaper.define_singleton_method(:chrome_group_alive?) { |_pid| true }
    reaper.define_singleton_method(:chrome_term_grace) { 0.0 }
    reaper.define_singleton_method(:chrome_kill_grace) { 0.0 }

    refute reaper.reap_chrome
    assert_equal 987_654_321, reaper.pid, "do not drop the retry handle when group exit is unproved"
  end

  def test_cdp_close_preserves_profile_when_chrome_shutdown_is_inconclusive
    Dir.mktmpdir("cdp-profile-preserve") do |profile|
      session = Deploy::CdpSession.allocate
      session.instance_variable_set(:@profile, profile)
      session.define_singleton_method(:reap_chrome) { false }

      refute session.close
      assert Dir.exist?(profile), "profile must remain available for diagnosis while Chrome may still be alive"
    end
  end

  private

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
      flunk "process #{pid} survived Chrome process-group teardown" if
        Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

      sleep 0.01
    end
  end
end
