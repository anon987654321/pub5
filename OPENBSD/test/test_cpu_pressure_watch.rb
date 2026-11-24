# frozen_string_literal: true

require "fileutils"
require "minitest/autorun"
require "open3"
require "tmpdir"

class CpuPressureWatchTest < Minitest::Test
  SOURCE = File.expand_path("../mirror/usr/local/bin/cpu-pressure-watch.sh", __dir__)

  def setup
    @dir = Dir.mktmpdir("cpu-pressure-watch")
    @bin = File.join(@dir, "bin")
    @state = File.join(@dir, "state")
    FileUtils.mkdir_p([@bin, @state])
    @alerts = File.join(@dir, "alerts.log")
    @script = File.join(@dir, "cpu-pressure-watch.sh")
    source = File.read(SOURCE).sub("ALERT_BIN=/usr/local/bin/pub5-alert", "ALERT_BIN=#{File.join(@bin, "pub5-alert")}")
    File.write(@script, source)
    File.chmod(0o755, @script)
    fake("vmstat", <<~SH)
      printf ' procs memory page disks traps cpu\\n'
      printf ' r s avm fre flt re pi po fr sr sd0 int sys cs us sy id\\n'
      printf '3 75 503M 327M 4566 0 0 0 0 1 14 17 3794 93 67 33 0\\n'
      i=1
      while [ "$i" -le "${FAKE_INTERVALS:-5}" ]; do
        idle=${FAKE_IDLE:-15}
        system=${FAKE_SYSTEM:-15}
        user=${FAKE_USER:-$((100 - idle - system))}
        printf '2 76 517M 313M 3661 0 0 0 0 0 0 9 8594 41 %s %s %s\\n' "$user" "$system" "$idle"
        i=$((i + 1))
      done
    SH
    fake("ps", <<~SH)
      printf 'PID PPID PGID USER STATE %%CPU TIME\\n'
      printf '123 1 123 _master R 85.0 00:10\\n'
      printf '124 1 124 _brgen R 40.0 00:08\\n'
      printf '125 1 125 _amber S 10.0 00:02\\n'
    SH
    fake("pub5-alert", 'printf "%s\\n" "$*" >> "$FAKE_ALERT_LOG"')
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def fake(name, body)
    path = File.join(@bin, name)
    File.write(path, ["#!/bin/sh", body].join("\n") + "\n")
    File.chmod(0o755, path)
  end

  def run_monitor(extra = {})
    Open3.capture3({
      "PUB5_CPU_PATH_PREFIX" => @dir,
      "PUB5_CPU_STATE_DIR" => @state,
      "PUB5_CPU_LOG" => File.join(@dir, "cpu.log"),
      "FAKE_ALERT_LOG" => @alerts
    }.merge(extra), ENV.fetch("PUB5_KSH", "ksh"), @script)
  end

  def test_five_high_cpu_samples_write_pressure_and_record_process_identity
    _, _, status = run_monitor

    assert status.success?
    stamp, busy = File.read(File.join(@state, "cpu-pressure")).split
    assert_match(/\A\d+\z/, stamp)
    assert_equal "85", busy
    assert_includes File.read(@alerts), "cpu-sustained"
    assert_includes File.read(File.join(@dir, "cpu.log")), "123 1 123 _master"
  end

  def test_quiet_samples_clear_the_pressure_signal
    File.write(File.join(@state, "cpu-pressure"), "#{Time.now.to_i} 88\n")
    _, _, status = run_monitor("FAKE_IDLE" => "99", "FAKE_SYSTEM" => "0")

    assert status.success?
    refute File.exist?(File.join(@state, "cpu-pressure"))
    assert_empty File.read(@alerts) if File.exist?(@alerts)
  end

  def test_incomplete_vmstat_sample_fails_without_claiming_a_heartbeat
    _, _, status = run_monitor("FAKE_INTERVALS" => "2")

    refute status.success?
    refute File.exist?(File.join(@state, "cpu-watch.seen"))
    assert_includes File.read(@alerts), "cpu-monitor-sample-failed"
  end

  def test_invalid_cpu_column_triplet_fails_without_claiming_a_heartbeat
    _, _, status = run_monitor("FAKE_IDLE" => "80", "FAKE_SYSTEM" => "30", "FAKE_USER" => "70")

    refute status.success?
    refute File.exist?(File.join(@state, "cpu-watch.seen"))
    assert_includes File.read(@alerts), "cpu-monitor-sample-failed"
  end
end
