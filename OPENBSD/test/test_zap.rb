# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "rbconfig"
require "stringio"
require_relative "../bin/zap"

class ZapTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  ZAP = File.join(ROOT, "OPENBSD", "bin", "zap.rb")

  def run_zap(*args, stdin: "")
    Open3.capture2e(RbConfig.ruby, ZAP, *args, stdin_data: stdin)
  end

  def test_help_is_available_without_a_package
    output, status = run_zap("--help")

    assert status.success?, output
    assert_includes output, "usage: zap"
    assert_includes output, "Linux/Android use /proc"
  end

  def test_missing_pattern_is_rejected
    output, status = run_zap

    refute status.success?
    assert_includes output, "expected one search pattern"
  end

  def test_unmatched_pattern_is_a_clean_noop
    marker = "zap-no-process-#{Process.pid}-#{object_id}"
    output, status = run_zap(marker)

    assert status.success?, output
    assert_includes output, "no processes match"
  end

  def test_force_mode_signals_only_the_matching_process
    marker = "zap-worker-#{Process.pid}-#{object_id}"
    child = Process.spawn(RbConfig.ruby, "-e", "sleep 30 # #{marker}")

    output, status = run_zap("-f", "-s", "TERM", marker)

    assert status.success?, output
    assert_includes output, "sent SIGTERM to PID #{child}"
    Process.wait(child)
  ensure
    if child
      begin
        Process.kill("KILL", child)
      rescue Errno::ESRCH
        nil
      end
      begin
        Process.wait(child)
      rescue Errno::ECHILD
        nil
      end
    end
  end

  def test_prompt_can_skip_a_matching_process
    marker = "zap-worker-#{Process.pid}-#{object_id}"
    child = Process.spawn(RbConfig.ruby, "-e", "sleep 30 # #{marker}")

    output, status = run_zap(marker, stdin: "n\n")

    assert status.success?, output
    assert_includes output, "#{child} "
    assert Process.kill(0, child)
  ensure
    if child
      begin
        Process.kill("KILL", child)
      rescue Errno::ESRCH
        nil
      end
      begin
        Process.wait(child)
      rescue Errno::ECHILD
        nil
      end
    end
  end

  def test_ps_fallback_works_without_procfs
    marker = "zap-ps-worker-#{Process.pid}-#{object_id}"
    child = Process.spawn(RbConfig.ruby, "-e", "sleep 30 # #{marker}")
    output = StringIO.new
    errors = StringIO.new
    zap = Zap.new(["-f", "-s", "TERM", marker], out: output, err: errors)
    zap.define_singleton_method(:linux_procfs?) { false }

    assert_equal 0, zap.run, errors.string
    assert_includes output.string, "sent SIGTERM to PID #{child}"
    Process.wait(child)
  ensure
    if child
      begin
        Process.kill("KILL", child)
      rescue Errno::ESRCH
        nil
      end
      begin
        Process.wait(child)
      rescue Errno::ECHILD
        nil
      end
    end
  end

  def test_classic_signal_spelling_is_supported
    marker = "zap-worker-#{Process.pid}-#{object_id}"
    child = Process.spawn(RbConfig.ruby, "-e", "sleep 30 # #{marker}")

    output, status = run_zap("-TERM", "-f", marker)

    assert status.success?, output
    assert_includes output, "sent SIGTERM to PID #{child}"
    Process.wait(child)
  ensure
    if child
      begin
        Process.kill("KILL", child)
      rescue Errno::ESRCH
        nil
      end
      begin
        Process.wait(child)
      rescue Errno::ECHILD
        nil
      end
    end
  end
end
