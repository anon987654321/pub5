# frozen_string_literal: true

require "fileutils"
require "minitest/autorun"
require "json"
require "rbconfig"
require "open3"
require "tmpdir"

# usr/local/bin/pub4-alert: the durable alert that a healed or noted symptom lands
# in. Every external read (df, swapctl, rcctl) is a fake first on PATH, and the
# log, state and marker are scratch paths, so nothing here touches the machine.
class TestPub4Alert < Minitest::Test
  SCRIPT = File.expand_path("../mirror/usr/local/bin/pub4-alert", __dir__)

  def fake(dir, name, body)
    FileUtils.mkdir_p(File.join(dir, "fake"))
    path = File.join(dir, "fake", name)
    File.write(path, "#!/bin/sh\n#{body}\n")
    File.chmod(0o755, path)
  end

  def env(dir, extra = {})
    {
      "PUB4_ALERT_PATH_PREFIX" => File.join(dir, "fake"),
      "PUB4_ALERT_LOG" => File.join(dir, "alerts.log"),
      "PUB4_ALERT_STATE" => File.join(dir, "state"),
      "PUB4_ALERT_LOGGER" => "true",
      "PUB4_DR_MARKER" => File.join(dir, "marker"),
      "PUB4_CPU_HISTORY" => File.join(dir, "cpu-watch.log"),
      "PUB4_CPU_PRESSURE" => File.join(dir, "cpu-pressure"),
      "PUB4_CPU_HEARTBEAT" => File.join(dir, "state", "cpu-watch.seen"),
      "PUB4_CPU_DEPLOY_FLAGS" => File.join(dir, "no-deploy-*"),
      "PUB4_ALERT_ADMIN" => File.join(dir, "fake", "pub5-admin"),
      "PUB4_ALERT_RUBY" => RbConfig.ruby,
    }.merge(extra)
  end

  def run_alert(dir, *args, **extra)
    out, err, status = Open3.capture3(env(dir, extra), ENV.fetch("PUB5_KSH", "ksh"), SCRIPT, *args)
    [out + err, status.exitstatus]
  end

  def log(dir)
    File.exist?(File.join(dir, "alerts.log")) ? File.read(File.join(dir, "alerts.log")) : ""
  end

  def quiet_box(dir)
    fake(dir, "df", %(echo "Filesystem 512-blocks Used Available Capacity Mounted on"; echo "/dev/sd0k 100 76 24 76% /home"))
    fake(dir, "swapctl", %(echo "total: 2588672 512-blocks allocated, 1000000 used, 1588672 available"))
    fake(dir, "rcctl", "exit 0")
    fake(dir, "pub5-admin", "printf '%s\\n' '#{JSON.generate("pending" => [], "truncated" => false, "scanned" => 0, "returned" => 0)}'")
    FileUtils.mkdir_p(File.join(dir, "state"))
    File.write(File.join(dir, "state", "cpu-watch.seen"), Time.now.to_i.to_s)
    File.write(File.join(dir, "marker"), Time.now.to_i.to_s)
  end

  def test_a_healthy_box_records_nothing
    Dir.mktmpdir do |dir|
      quiet_box(dir)
      _, status = run_alert(dir, "watch")

      assert_equal 0, status
      assert_equal "", log(dir)
    end
  end

  def test_raise_records_once_per_key_in_the_quiet_window_and_again_after_it
    Dir.mktmpdir do |dir|
      run_alert(dir, "raise", "relayd-restarts", "relayd restarted 3 times")
      run_alert(dir, "raise", "relayd-restarts", "relayd restarted 4 times")
      run_alert(dir, "raise", "other", "a different fault")

      assert_equal 2, log(dir).lines.size, log(dir)
      assert_match(/\A\d{4}-\d\d-\d\dT[\d:]+Z relayd-restarts relayd restarted 3 times$/, log(dir).lines.first)

      run_alert(dir, "raise", "relayd-restarts", "still failing", "PUB4_ALERT_QUIET" => "0")
      assert_includes log(dir), "relayd-restarts still failing"
    end
  end

  def test_raise_refuses_a_key_that_could_escape_the_state_directory
    Dir.mktmpdir do |dir|
      _, status = run_alert(dir, "raise", "../x", "nope")

      assert_equal 2, status
      assert_equal "", log(dir)
    end
  end

  def test_watch_names_a_full_filesystem_with_the_command_to_find_the_growth
    Dir.mktmpdir do |dir|
      quiet_box(dir)
      fake(dir, "df", %(echo "Filesystem 512-blocks Used Available Capacity Mounted on"; echo "/dev/sd0k 100 95 5 95% /home"; echo "/dev/sd0a 100 20 80 20% /"))
      run_alert(dir, "watch")

      assert_includes log(dir), "disk-home /home is 95% full"
      assert_includes log(dir), "doas /usr/local/sbin/pub4-admin disk-usage /home"
      refute_includes log(dir), "disk-root"
    end
  end

  def test_watch_names_swap_pressure
    Dir.mktmpdir do |dir|
      quiet_box(dir)
      fake(dir, "swapctl", %(echo "total: 2588672 512-blocks allocated, 2500000 used, 88672 available"))
      run_alert(dir, "watch")

      assert_includes log(dir), "swap swap is 96% used"
    end
  end

  def test_watch_ignores_the_designed_failure_and_names_any_other
    Dir.mktmpdir do |dir|
      quiet_box(dir)
      fake(dir, "rcctl", %(printf 'brgen_jobs\\nsmtpd\\n'))
      run_alert(dir, "watch")

      refute_includes log(dir), "failed-brgen_jobs"
      assert_includes log(dir), "failed-smtpd smtpd is in rcctl failed"
    end
  end

  def test_watch_flags_a_missing_and_a_stale_backup_report
    Dir.mktmpdir do |dir|
      quiet_box(dir)
      File.delete(File.join(dir, "marker"))
      run_alert(dir, "watch")
      assert_includes log(dir), "backup-unreported"

      File.write(File.join(dir, "marker"), (Time.now.to_i - 4 * 86_400).to_s)
      run_alert(dir, "watch")
      assert_match(/backup-stale the newest dr-pull reported 96 hours ago/, log(dir))
    end
  end

  def fake_cpu(dir, user:, system:, idle:)
    row = "0 0 0 0 0 0 0 0 0 0 0 #{user} #{system} #{idle}"
    lines = ["echo 'procs memory page disk traps cpu'", "echo 'r b avm fre flt re pi po fr sr x y z us sy id'"]
    6.times { lines << "echo '#{row}'" }
    fake(dir, "vmstat", lines.join("\n"))
    fake(dir, "ps", "echo 'PCPU PID PPID USER STAT TIME COMMAND'; echo '84.0 123 1 root R 00:05 ruby'; echo '9.0 99 1 _nsd S 00:02 nsd'")
  end

  def test_cpu_watch_needs_three_high_busy_samples_and_records_process_names_only
    Dir.mktmpdir do |dir|
      quiet_box(dir)
      fake_cpu(dir, user: 75, system: 10, idle: 15)

      2.times { run_alert(dir, "cpu-watch") }
      refute_includes log(dir), "cpu-saturation"

      _, status = run_alert(dir, "cpu-watch")
      assert_equal 0, status
      assert_includes log(dir), "cpu-saturation CPU busy 85%"
      assert_includes log(dir), "ruby"
      refute_includes log(dir), "ruby -"
      assert File.file?(File.join(dir, "cpu-pressure")), "active CPU pressure must be visible to resource_guard"
      assert File.file?(File.join(dir, "state", "cpu-watch.seen")), "successful sampling must refresh the heartbeat"
      assert_equal 3, File.readlines(File.join(dir, "cpu-watch.log")).size
    end
  end

  def test_cpu_watch_raises_critical_after_two_95_percent_samples
    Dir.mktmpdir do |dir|
      quiet_box(dir)
      fake_cpu(dir, user: 90, system: 8, idle: 2)

      run_alert(dir, "cpu-watch")
      refute_includes log(dir), "cpu-critical"
      run_alert(dir, "cpu-watch")
      assert_includes log(dir), "cpu-critical CPU busy 98%"
    end
  end

  def test_cpu_watch_allows_a_longer_sustained_window_during_deploy
    Dir.mktmpdir do |dir|
      quiet_box(dir)
      flag = File.join(dir, ".deploying-test")
      File.write(flag, "")
      fake_cpu(dir, user: 75, system: 10, idle: 15)

      3.times { run_alert(dir, "cpu-watch", "PUB4_CPU_DEPLOY_FLAGS" => flag, "PUB4_CPU_DEPLOY_STRIKES" => "4") }
      refute_includes log(dir), "cpu-saturation"
      run_alert(dir, "cpu-watch", "PUB4_CPU_DEPLOY_FLAGS" => flag, "PUB4_CPU_DEPLOY_STRIKES" => "4")
      assert_includes log(dir), "cpu-saturation CPU busy 85%"
    end
  end

  def test_cpu_pressure_clears_only_after_three_quiet_samples
    Dir.mktmpdir do |dir|
      quiet_box(dir)
      fake_cpu(dir, user: 75, system: 10, idle: 15)
      3.times { run_alert(dir, "cpu-watch") }
      assert File.file?(File.join(dir, "cpu-pressure"))

      fake_cpu(dir, user: 10, system: 5, idle: 85)
      2.times { run_alert(dir, "cpu-watch") }
      assert File.file?(File.join(dir, "cpu-pressure"))
      refute_includes log(dir), "cpu-recovered"

      run_alert(dir, "cpu-watch")
      refute File.exist?(File.join(dir, "cpu-pressure"))
      assert_includes log(dir), "cpu-recovered CPU recovered to 15%"
    end
  end

  def test_watch_alerts_when_cpu_monitor_heartbeat_is_missing
    Dir.mktmpdir do |dir|
      quiet_box(dir)
      File.delete(File.join(dir, "state", "cpu-watch.seen"))
      run_alert(dir, "watch")
      assert_includes log(dir), "cpu-watch-stale CPU monitor heartbeat is missing"
    end
  end

  def test_cpu_watch_is_scheduled_once_per_minute_and_its_log_is_rotated
    root = File.expand_path("../..", __dir__)
    crontab = File.read(File.join(root, "OPENBSD", "data", "root.crontab"))
    newsyslog = File.read(File.join(root, "OPENBSD", "mirror", "etc", "newsyslog.conf"))

    assert_includes crontab, "* * * * * -s /usr/local/bin/pub4-alert cpu-watch >> /var/log/cpu-watch.log 2>&1"
    assert_includes newsyslog, "/var/log/cpu-watch.log                   root:wheel 640 12 250 $W0D0 Z"
  end

  def process_identity(pid)
    started, start_status = Open3.capture2({ "LC_ALL" => "C" }, "ps", "-p", pid.to_s, "-o", "lstart=")
    command, command_status = Open3.capture2("ps", "-ww", "-p", pid.to_s, "-o", "command=")
    raise "could not read current process identity" unless start_status.success? && command_status.success?
    started = started.sub(/\n+\z/, "")
    command = command.sub(/\n+\z/, "")
    checksum, checksum_status = Open3.capture2("cksum", stdin_data: command)
    raise "could not checksum current process command" unless checksum_status.success?
    "#{started.gsub(/[^A-Za-z0-9]/, "_")}_#{checksum.strip.tr(" ", "_")}"
  end

  def recovery_receipt(run_id:, pid:, status: "running", snapshot_recorded: true, owner_identity: "Tue_Nov_17_01_00_00_2026_123_456")
    {
      schema: 1,
      run_id: run_id,
      target: "all",
      host: "vm23",
      pid: pid,
      owner_identity: owner_identity,
      status: status,
      recovery_state: "pending",
      stage: "restart-brgen",
      started_at: "2026-11-17T01:00:00Z",
      updated_at: "2026-11-17T01:01:00Z",
      pinned_sha: "a" * 40,
      previous_sha: "b" * 40,
      started_services: %w[master brgen],
      ports: { "master" => 53187, "brgen" => 38182 },
      restore_order: %w[brgen master],
      run_log: "/var/log/pub5/runs/deploy-20261117-all-12345.log",
      aggregate_log: "/var/log/pub5/vps-deploy.log",
      snapshot_recorded: snapshot_recorded,
    }
  end

  def fake_run_list(dir, records, truncated: false, scanned: records.length)
    document = {
      "pending" => records,
      "truncated" => truncated,
      "scanned" => scanned,
      "returned" => records.length,
    }
    fake(dir, "pub5-admin", "printf '%s\\n' '#{JSON.generate(document)}'")
  end

  def test_watch_alerts_when_pending_receipt_scan_is_truncated
    Dir.mktmpdir do |dir|
      quiet_box(dir)
      fake_run_list(dir, [], truncated: true, scanned: 501)

      _, status = run_alert(dir, "watch")

      assert_equal 0, status
      assert_includes log(dir), "deploy-recovery-scan-truncated"
      assert_includes log(dir), "bounded window"
      assert_includes log(dir), "recover --plan"
    end
  end

  def test_watch_alerts_when_a_pending_deploy_owner_has_exited
    Dir.mktmpdir do |dir|
      quiet_box(dir)
      run_id = "20261117T010000Z-all-12345"
      fake_run_list(dir, [recovery_receipt(run_id:, pid: 2_000_000_000)])

      _, status = run_alert(dir, "watch")

      assert_equal 0, status
      assert_includes log(dir), "deploy-recovery-#{run_id}"
      assert_includes log(dir), "interrupted deploy #{run_id}"
      assert_includes log(dir), "inspect with: zsh OPENBSD/bin/vps-deploy recover --plan"
      assert_includes log(dir), "/var/log/pub5/runs/deploy-20261117-all-12345.log"
    end
  end

  def test_watch_does_not_alert_while_the_receipt_owner_pid_is_alive
    Dir.mktmpdir do |dir|
      quiet_box(dir)
      run_id = "20261117T010001Z-all-12346"
      identity = process_identity(Process.pid)
      fake_run_list(dir, [recovery_receipt(run_id:, pid: Process.pid, owner_identity: identity)])

      _, status = run_alert(dir, "watch")

      assert_equal 0, status
      refute_includes log(dir), "deploy-recovery-#{run_id}"
    end
  end

  def test_watch_alerts_when_the_recorded_pid_is_reused_by_another_process
    Dir.mktmpdir do |dir|
      quiet_box(dir)
      run_id = "20261117T010004Z-all-12349"
      fake_run_list(dir, [recovery_receipt(run_id:, pid: Process.pid, owner_identity: "different_process_fingerprint")])

      _, status = run_alert(dir, "watch")

      assert_equal 0, status
      assert_includes log(dir), "deploy-recovery-#{run_id}"
      assert_includes log(dir), "owner PID #{Process.pid} is reused"
    end
  end

  def test_watch_alerts_for_an_incomplete_snapshot_without_claiming_it_is_recoverable
    Dir.mktmpdir do |dir|
      quiet_box(dir)
      run_id = "20261117T010002Z-all-12347"
      fake_run_list(dir, [recovery_receipt(run_id:, pid: 2_000_000_000, status: "failed", snapshot_recorded: false)])

      run_alert(dir, "watch")

      assert_includes log(dir), "snapshot=incomplete"
      assert_includes log(dir), "recover --plan"
    end
  end

  def test_watch_reports_an_unavailable_or_malformed_recovery_broker
    Dir.mktmpdir do |dir|
      quiet_box(dir)
      fake(dir, "pub5-admin", "printf '{broken\\n'")
      run_alert(dir, "watch")

      assert_includes log(dir), "deploy-recovery-status-unavailable"
      assert_includes log(dir), "cannot parse fleet deploy receipts"
    end
  end

  def test_existing_five_minute_watch_covers_fleet_recovery_receipts
    root = File.expand_path("../..", __dir__)
    crontab = File.read(File.join(root, "OPENBSD", "data", "root.crontab"))
    source = File.read(SCRIPT)

    assert_includes crontab, "*/5 * * * * /usr/local/bin/pub4-alert watch"
    assert_includes source, "watch_deploy_recovery"
    assert_includes source, 'deploy-run-pending-list'
    assert_includes source, 'ps", "-p", pid.to_s, "-o", "lstart="'
    assert_includes source, 'ps", "-ww", "-p", pid.to_s, "-o", "command="'
    assert_includes source, 'Open3.capture2("cksum", stdin_data: command)'
    assert_includes source, "deploy-recovery-scan-truncated"
  end

  def test_show_prints_the_last_alerts
    Dir.mktmpdir do |dir|
      3.times { |i| run_alert(dir, "raise", "k#{i}", "message #{i}") }
      out, status = run_alert(dir, "show", "2")

      assert_equal 0, status
      assert_equal 2, out.lines.size
      assert_includes out, "k2 message 2"
      refute_includes out, "k0"
    end
  end
end
