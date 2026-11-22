# frozen_string_literal: true

require_relative "test_helper"
require "rbconfig"
require "tmpdir"
require_relative "../lib/operator/checks"

class TestOperatorScanSupervision < Minitest::Test
  def test_scan_timeout_includes_pipe_eof_after_the_leader_exits
    Dir.mktmpdir("constitutional-scan-supervision") do |dir|
      child_pid_file = File.join(dir, "descendant.pid")
      child_code = "File.write(#{child_pid_file.dump}, Process.pid.to_s); sleep 60"
      launcher_code = "require 'rbconfig'; Process.spawn(RbConfig.ruby, '-e', #{child_code.dump})"
      fake_bundle = File.join(dir, "fake-bundle.rb")
      File.write(fake_bundle, launcher_code)

      check = Deploy::ConstitutionalScanCheck.allocate
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      _output, status = check.send(
        :bounded_scan, "/scan --no-autofix MASTER",
        ruby: RbConfig.ruby, bundle: fake_bundle, master: dir, timeout: 0.2
      )
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

      child = Integer(File.read(child_pid_file), 10)
      assert_equal :timeout, status
      assert_operator elapsed, :<, 3.0, "a descendant holding stdout must not turn the timeout into an unbounded wait"
      assert_process_gone(child)
    end
  end

  private

  def assert_process_gone(pid)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 2
    loop do
      begin
        Process.kill(0, pid)
      rescue Errno::ESRCH
        return
      end
      flunk "scan descendant #{pid} survived the bounded process-group teardown" if
        Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

      sleep 0.01
    end
  end
end
