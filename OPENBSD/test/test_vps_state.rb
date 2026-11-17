# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "fileutils"
require "json"
require "rbconfig"
require "tmpdir"

# vps-state is what an operator reads first, so a failed stamp and a recorded
# alert must both show in it. DEPLOY_ASSUME_VPS=1 runs the box path on any host;
# the service reads degrade to "unknown" without doas.
class TestVpsState < Minitest::Test
  SCRIPT = File.expand_path("../bin/vps-state", __dir__)

  def state(dir, *args)
    env = { "DEPLOY_ASSUME_VPS" => "1", "PUB4_STAMP_DIR" => dir, "PUB4_ALERT_LOG" => File.join(dir, "alerts.log") }
    out, err, status = Open3.capture3(env, RbConfig.ruby, SCRIPT, *args)
    assert status.success?, err
    out
  end

  def write_run(dir, run_id:, pid:, status: "running", snapshot_recorded: true)
    directory = File.join(dir, "deploy_runs")
    FileUtils.mkdir_p(directory)
    record = {
      "schema" => 1,
      "run_id" => run_id,
      "target" => "all",
      "host" => "vm23",
      "pid" => pid,
      "owner_identity" => "Tue_Nov_17_01_00_00_2026_123_456",
      "status" => status,
      "recovery_state" => "pending",
      "stage" => "restart-brgen",
      "started_at" => "2026-11-17T01:00:00Z",
      "updated_at" => "2026-11-17T01:01:00Z",
      "pinned_sha" => "a" * 40,
      "previous_sha" => "b" * 40,
      "started_services" => %w[master brgen],
      "ports" => { "master" => 53187, "brgen" => 38182 },
      "restore_order" => %w[brgen master],
      "run_log" => "/var/log/pub5/runs/deploy-20261117-all-12345.log",
      "aggregate_log" => "/var/log/pub5/vps-deploy.log",
      "snapshot_recorded" => snapshot_recorded,
    }
    path = File.join(directory, "#{run_id}.json")
    File.write(path, JSON.generate(record))
    File.chmod(0o600, path)
    path
  end

  def test_a_failed_last_deploy_shows_its_status
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "last_deploy_amber.json"), '{"app":"amber","sha":"abc123","at":"2026-10-10T09:29:57Z","status":"failed"}')

      assert_match(/deploy0 at amber: sha=abc123 at=\S+ status=failed/, state(dir))
    end
  end

  def test_production_status_reader_uses_fixed_broker_verb
    source = File.read(SCRIPT)

    assert_includes source, 'Open3.capture2e("doas", "-n", broker, "deploy-status-read", app)'
    assert_includes source, 'broker = "/usr/local/sbin/pub5-admin"'
    assert_includes source, 'Open3.capture2e("doas", "-n", broker, "deploy-run-list")'
    assert_includes source, 'def deploy_recovery_status'
    assert_includes source, 'status["unavailable"] ? "unavailable"'
    assert_includes source, 'File.expand_path(STAMP_DIR) == "/var/db/pub4"'
  end

  def test_corrupt_in_progress_deploy_status_is_visible
    Dir.mktmpdir do |dir|
      status_dir = File.join(dir, "deploy_status")
      FileUtils.mkdir_p(status_dir)
      File.write(File.join(status_dir, "amber.json"), "{broken json")

      output = state(dir)

      assert_match(/deploy0 at amber: state=corrupt step=status metadata corrupt/, output)
      assert_match(/JSON::ParserError/, output)
    end
  end

  def test_pending_recovery_receipt_is_visible_in_text_output
    Dir.mktmpdir do |dir|
      run_id = "20261117T010000Z-all-12345"
      write_run(dir, run_id:, pid: 2_000_000_000)

      output = state(dir)

      assert_match(/recovery0 at fleet: state=pending pending=1/, output)
      assert_match(/recovery0 at #{Regexp.escape(run_id)}: target=all status=running owner_pid_state=gone snapshot=complete stage=restart-brgen/, output)
      assert_includes output, "inspect=zsh OPENBSD/bin/vps-deploy recover --plan"
    end
  end

  def test_pending_recovery_receipt_is_in_json_with_owner_and_snapshot_state
    Dir.mktmpdir do |dir|
      run_id = "20261117T010001Z-all-12346"
      write_run(dir, run_id:, pid: Process.pid, status: "failed", snapshot_recorded: false)

      payload = JSON.parse(state(dir, "--json"))
      recovery = payload.fetch("deploy_recovery")

      assert_equal "pending", recovery.fetch("state")
      assert_equal 1, recovery.fetch("count")
      row = recovery.fetch("pending").first
      assert_equal run_id, row.fetch("run_id")
      assert_equal "present", row.fetch("pid_state")
      assert_equal "incomplete", row.fetch("snapshot")
      assert_equal "restart-brgen", row.fetch("stage")
      assert_equal "/var/log/pub5/runs/deploy-20261117-all-12345.log", row.fetch("run_log")
    end
  end

  def test_completed_recovery_receipts_do_not_appear_as_pending
    Dir.mktmpdir do |dir|
      run_id = "20261117T010002Z-all-12347"
      path = write_run(dir, run_id:, pid: 2_000_000_000)
      record = JSON.parse(File.read(path))
      record["recovery_state"] = "complete"
      record["status"] = "recovered"
      File.write(path, JSON.generate(record))

      payload = JSON.parse(state(dir, "--json"))
      assert_equal "none", payload.fetch("deploy_recovery").fetch("state")
      assert_empty payload.fetch("deploy_recovery").fetch("pending")
    end
  end

  def test_corrupt_fleet_receipt_is_not_silently_reported_as_no_pending_runs
    Dir.mktmpdir do |dir|
      directory = File.join(dir, "deploy_runs")
      FileUtils.mkdir_p(directory)
      path = File.join(directory, "20261117T010003Z-all-12348.json")
      File.write(path, "{broken")
      File.chmod(0o600, path)

      payload = JSON.parse(state(dir, "--json"))
      recovery = payload.fetch("deploy_recovery")
      refute_equal "none", recovery.fetch("state")
      assert_match(/corrupt/i, recovery.fetch("error"))
    end
  end

  def test_recorded_alerts_show_newest_first_and_a_quiet_box_shows_none
    Dir.mktmpdir do |dir|
      refute_includes state(dir), "alert0"

      File.write(File.join(dir, "alerts.log"), "2026-10-12T01:00:00Z swap first\n2026-10-12T02:00:00Z disk-home second\n")
      lines = state(dir).lines.grep(/alert0/)

      assert_equal 2, lines.size
      assert_includes lines.first, "disk-home second"
    end
  end
end
