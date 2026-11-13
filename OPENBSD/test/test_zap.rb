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

    output, status = run_zap("-f", marker)

    assert status.success?, output
    assert_includes output, "sent SIGTERM to PID #{child}"
    Process.wait(child)
  ensure
    reap_child(child)
  end

  def test_prompt_can_skip_a_matching_process
    marker = "zap-worker-#{Process.pid}-#{object_id}"
    child = Process.spawn(RbConfig.ruby, "-e", "sleep 30 # #{marker}")

    output, status = run_zap(marker, stdin: "n\n")

    assert status.success?, output
    assert_includes output, "#{child} "
    assert Process.kill(0, child)
  ensure
    reap_child(child)
  end

  def test_ps_fallback_works_without_procfs
    marker = "zap-ps-worker-#{Process.pid}-#{object_id}"
    child = Process.spawn(RbConfig.ruby, "-e", "sleep 30 # #{marker}")
    output = StringIO.new
    errors = StringIO.new
    zap = Zap.new(["-f", marker], out: output, err: errors)
    zap.define_singleton_method(:linux_procfs?) { false }

    assert_equal 0, zap.run, errors.string
    assert_includes output.string, "sent SIGTERM to PID #{child}"
    Process.wait(child)
  ensure
    reap_child(child)
  end

  def test_default_signal_is_term
    zap, output, _errors, sent = build_zap(["-f", "worker"], processes: [process(210, "worker --serve")])

    assert_equal 0, zap.run
    assert_equal [[Signal.list.fetch("TERM"), 210]], sent
    assert_includes output.string, "sent SIGTERM to PID 210"
  end

  def test_classic_signal_spelling_is_supported
    zap, _output, _errors, sent = build_zap(["-KILL", "-f", "worker"], processes: [process(211, "worker")])

    assert_equal 0, zap.run
    assert_equal [[Signal.list.fetch("KILL"), 211]], sent
  end

  def test_signal_option_accepts_signal_prefix
    zap, _output, _errors, sent = build_zap(["-f", "-s", "SIGINT", "worker"], processes: [process(212, "worker")])

    assert_equal 0, zap.run
    assert_equal [[Signal.list.fetch("INT"), 212]], sent
  end

  def test_dry_run_lists_matches_without_signalling
    zap, output, _errors, sent = build_zap(["--dry-run", "worker"], processes: [process(213, "worker")])

    assert_equal 0, zap.run
    assert_empty sent
    assert_includes output.string, "would send SIGTERM to PID 213"
  end

  def test_openbsd_vmd_is_never_signalled_even_with_force
    zap, _output, errors, sent = build_zap(
      ["-f", "vmd"], processes: [process(214, "/usr/sbin/vmd -f /etc/vm.conf")]
    )

    assert_equal 2, zap.run
    assert_empty sent
    assert_includes errors.string, "vmctl stop <vm>"
  end

  def test_openbsd_vmctl_and_console_processes_are_protected
    %w[/usr/sbin/vmctl cu].each do |command|
      zap, _output, errors, sent = build_zap(
        ["-f", File.basename(command)], processes: [process(215, command)]
      )

      assert_equal 2, zap.run
      assert_empty sent
      assert_includes errors.string, "refusing to signal"
    end
  end

  def test_vmd_name_is_not_special_on_other_platforms
    zap, _output, _errors, sent = build_zap(
      ["-f", "vmd"], processes: [process(216, "vmd")], platform: "linux"
    )

    assert_equal 0, zap.run
    assert_equal [[Signal.list.fetch("TERM"), 216]], sent
  end

  def test_invalid_signal_fails_before_signalling
    zap, _output, errors, sent = build_zap(
      ["-NOSUCH", "worker"], processes: [process(217, "worker")]
    )

    assert_equal 2, zap.run
    assert_empty sent
    assert_includes errors.string, "unknown signal"
  end

  private

  def process(pid, command)
    { pid: pid, command: command, identity: [:test, pid] }
  end

  def build_zap(argv, processes:, platform: "openbsd")
    output = StringIO.new
    errors = StringIO.new
    sent = []
    zap = Zap.new(
      argv,
      out: output,
      err: errors,
      input: StringIO.new,
      process_provider: -> { processes },
      signaler: ->(signal, pid) { sent << [signal, pid] },
      platform: platform
    )
    zap.define_singleton_method(:same_process?) { |_process| true }
    [zap, output, errors, sent]
  end

  def reap_child(child)
    return unless child

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
