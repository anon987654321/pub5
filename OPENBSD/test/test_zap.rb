# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "rbconfig"
require "stringio"
require_relative "../bin/zap.rb"

class ZapTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  ZAP = File.join(ROOT, "OPENBSD", "bin", "zap.rb")

  def run_zap(*args)
    Open3.capture2e(RbConfig.ruby, ZAP, *args)
  end

  def test_help_describes_exact_kill_by_name_contract
    output, status = run_zap("--help")

    assert status.success?, output
    assert_includes output, "process name contains keyword"
    assert_includes output, "SIGKILL (9)"
    assert_includes output, "--dry-run"
  end

  def test_keyword_is_required
    output, status = run_zap

    refute status.success?
    assert_includes output, "expected one process-name keyword"
  end

  def test_keyword_matches_process_name_as_a_substring
    zap, output, _errors, sent = build_zap(
      ["ruby"],
      processes: [
        process(210, "ruby3.4"),
        process(211, "python"),
        process(212, "worker-ruby-helper")
      ]
    )

    assert_equal 0, zap.run
    assert_equal [[9, 210], [9, 212]], sent
    assert_includes output.string, "killed -9 210 ruby3.4"
    assert_includes output.string, "killed 2 process(es)"
  end

  def test_keyword_does_not_match_arguments
    zap, output, _errors, sent = build_zap(
      ["secret"],
      processes: [process(213, "ruby")]
    )

    assert_equal 0, zap.run
    assert_empty sent
    assert_includes output.string, "no process name matches"
  end

  def test_dry_run_never_signals
    zap, output, _errors, sent = build_zap(
      ["--dry-run", "ruby"],
      processes: [process(214, "ruby-worker")]
    )

    assert_equal 0, zap.run
    assert_empty sent
    assert_includes output.string, "would kill -9 214 ruby-worker"
  end

  def test_unmatched_keyword_is_a_clean_noop
    zap, output, _errors, sent = build_zap(
      ["missing"],
      processes: [process(215, "ruby")]
    )

    assert_equal 0, zap.run
    assert_empty sent
    assert_includes output.string, "no process name matches"
  end

  def test_changed_pid_identity_is_not_killed
    zap, output, _errors, sent = build_zap(
      ["worker"],
      processes: [process(216, "worker")]
    )
    zap.define_singleton_method(:same_process?) { |_candidate| false }

    assert_equal 0, zap.run
    assert_empty sent
    assert_includes output.string, "changed or exited; skipped"
  end

  def test_permission_failure_is_reported
    output = StringIO.new
    errors = StringIO.new
    zap = Zap.new(
      ["worker"],
      out: output,
      err: errors,
      process_provider: -> { [process(217, "worker")] },
      signaler: ->(_signal, _pid) { raise Errno::EPERM },
      platform: "linux"
    )
    zap.define_singleton_method(:same_process?) { |_candidate| true }

    assert_equal 1, zap.run
    assert_includes errors.string, "cannot kill PID 217"
  end

  def test_android_toybox_parser_reads_process_name_not_arguments
    zap = Zap.new(["--help"], platform: "android")
    parsed = zap.send(:parse_android_ps_line, "412 1 com.example.worker")

    assert_equal 412, parsed[:pid]
    assert_equal "com.example.worker", parsed[:name]
    assert_equal [:ps_android, 1, "com.example.worker"], parsed[:identity]
  end

  def test_bsd_parser_reads_ucomm_not_command_line
    zap = Zap.new(["--help"], platform: "openbsd")
    parsed = zap.send(:parse_unix_ps_line, "412 1 00:03:14 nsd: worker")

    assert_equal 412, parsed[:pid]
    assert_equal "nsd: worker", parsed[:name]
    assert_equal [:ps, 1, "00:03:14", "nsd: worker"], parsed[:identity]
  end

  def test_vmd_is_matched_by_its_process_name_like_any_other_process
    zap, _output, _errors, sent = build_zap(
      ["vmd"],
      processes: [process(218, "vmd")]
    )

    assert_equal 0, zap.run
    assert_equal [[9, 218]], sent
  end

  def test_linux_procfs_integration_sends_sigkill_to_matching_comm
    skip "Linux /proc required" unless RUBY_PLATFORM.include?("linux") && File.writable?("/proc/self/comm")

    marker = "z#{Process.pid}q"
    child_code = 'File.write("/proc/self/comm", ARGV.fetch(0)); sleep 30'
    child = Process.spawn(RbConfig.ruby, "-e", child_code, marker)

    wait_until do
      File.read("/proc/#{child}/comm").chomp == marker
    end

    output, status = run_zap(marker)

    assert status.success?, output
    assert_includes output, "killed -9 #{child} #{marker}"
    Process.wait(child)
  ensure
    reap_child(child)
  end

  private

  def process(pid, name)
    { pid: pid, name: name, identity: [:test, pid, name] }
  end

  def build_zap(argv, processes:, platform: "linux")
    output = StringIO.new
    errors = StringIO.new
    sent = []
    zap = Zap.new(
      argv,
      out: output,
      err: errors,
      process_provider: -> { processes },
      signaler: ->(signal, pid) { sent << [signal, pid] },
      platform: platform
    )
    zap.define_singleton_method(:same_process?) { |_candidate| true }
    [zap, output, errors, sent]
  end

  def wait_until
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 3
    until yield
      raise "timed out waiting for child process name" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

      sleep 0.01
    end
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
