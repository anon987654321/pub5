# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "fileutils"
require "json"
require "operator/fix_status"

class TestFixStatus < Minitest::Test
  def setup
    @root = Dir.mktmpdir("fix-status-")
    FileUtils.mkdir_p(File.join(@root, "MASTER", ".master"))
    FileUtils.mkdir_p(File.join(@root, ".master"))
  end

  def teardown = FileUtils.rm_rf(@root)

  def write(path, body)
    File.write(File.join(@root, "MASTER", ".master", path), body)
  end

  # /fix keeps its mission at the repository root, its journal under MASTER.
  def write_mission(body)
    File.write(File.join(@root, ".master", "mission.json"), body)
  end

  def run_record(target, state: "active", pid: Process.pid)
    {
      "id" => "abcdef0123456789", "state" => state, "target" => File.join(@root, target),
      "files" => %w[a.rb b.rb], "max_passes" => 7, "pid" => pid, "started_at" => "2026-10-11T10:00:00Z",
      "passes" => [{ "pass" => 1, "state" => "done" }, { "pass" => 2, "state" => "active" }]
    }
  end

  def test_queue_follows_the_order_the_trees_were_typed
    assert_equal %w[RAILS STUDIO], Operator::FixStatus.queue_from("bin/master /fix RAILS STUDIO")
    assert_equal %w[STUDIO MASTER], Operator::FixStatus.queue_from("bin/master /fix STUDIO MASTER STUDIO")
    assert_equal %w[RAILS], Operator::FixStatus.queue_from("bin/master /fix RAILS")
    assert_empty Operator::FixStatus.queue_from("bin/master /fix RAILS/brgen/app")
  end

  def test_queue_uses_dispatch_target_parsing_for_flags
    status = Operator::FixStatus

    assert_equal %w[RAILS BIZ], status.queue_from("bin/master /fix --lane code RAILS,BIZ --only fix")
    assert_equal %w[STUDIO MASTER], status.queue_from("bin/master /fix --mode audit STUDIO MASTER --quiet")
    assert_empty status.queue_from("bin/master /fix --mode unknown RAILS MASTER")
    assert_empty status.queue_from("bin/master /fix --prove RAILS MASTER")
  end

  def test_single_tree_is_one_target_and_many_follow_argument_order
    root = "/tmp/pub5"
    registry = Master::CLI::CommandRegistry

    assert_equal ["RAILS"], registry.send(:fix_targets, "RAILS", root:)
    reversed = registry.send(:fix_targets, "STUDIO RAILS", root:)
    assert_equal %w[STUDIO RAILS].map { |tree| File.join(root, tree) }, reversed
  end

  def test_reads_the_journal_mission_and_logs_without_writing
    runs = [run_record("RAILS"), run_record("STUDIO", state: "crashed", pid: 0)]
    write("fix_runs.json", JSON.generate("version" => 1, "runs" => runs))
    mission = { "state" => "running", "stage" => "execute", "scope" => "RAILS",
                "attempt_count" => 2, "artifacts" => %w[x] }
    write_mission(JSON.generate(mission))
    write("fix-RAILS.log", "first\nlast line\n")
    before = Dir.glob(File.join(@root, "**", "*"), File::FNM_DOTMATCH).sort

    payload = Operator::FixStatus.new(root: @root).payload

    assert_equal %w[RAILS STUDIO], payload[:runs].map { |row| row[:tree] }
    rails = payload[:runs].first
    assert_equal [2, 7, 2, true], [rails[:pass], rails[:max_passes], rails[:files], rails[:alive]]
    assert_equal "last line", payload[:logs].first[:last]
    assert_equal 2, payload[:mission][:attempts]
    assert_equal before, Dir.glob(File.join(@root, "**", "*"), File::FNM_DOTMATCH).sort
  end

  def test_tail_keeps_history_but_status_requires_a_live_receipt
    beat = "fix0: pass 2/8 scan0 files 812/2638 (31%) fixes 1 ok 0 failed tokens = 5 (5) elapsed = 60s (1m00s) eta ~3m load 1.0"
    write("fix-RAILS.log", "#{beat.sub("812", "700")}\nscan0: 9/10 a.rb\n#{beat}\n" \
      "fix0 phase=stream fixed=3 failed=1 rejected=0 lane=free elapsed=62\n" \
      "budget0: spent\n")

    status = Operator::FixStatus.new(root: @root)

    assert_equal "no live receipt", status.payload[:heartbeat]
    assert_includes status.render, "heartbeat: no live receipt"
    out = StringIO.new
    require "operator/fix_tail"
    Operator::FixTail.run(%w[--once --tail=2], roots: [File.join(@root, "MASTER")], io: out)
    assert_equal "#{beat}\nbudget0: spent\n", out.string
  end

  def test_status_does_not_present_a_dead_active_record_as_running
    write("fix_runs.json", JSON.generate("runs" => [run_record("RAILS", pid: 0)]))

    rendered = Operator::FixStatus.new(root: @root).render(detail: true)

    refute_includes rendered, "fix0: active tree=RAILS"
  end

  def test_process_listing_drops_a_dead_fix_pid
    dead = 999_999_999
    listing = "#{dead} 00:01 ruby MASTER/bin/master /fix RAILS\n"
    success = Struct.new(:success?).new(true)
    status = Operator::FixStatus.new(root: @root)

    Master::Io::Exec.stub(:capture2, [listing, success]) do
      assert_empty status.send(:processes)
    end
  end

  def test_historical_heartbeat_cannot_describe_a_dead_receipt
    write("fix_runs.json", JSON.generate("runs" => [run_record("RAILS", pid: 0)]))
    write("fix-RAILS.log", "fix0: pass 1/8 scan0 files 1/2\n")

    assert_equal "no live receipt", Operator::FixStatus.new(root: @root).payload[:heartbeat]
  end

  def test_live_process_without_a_receipt_is_not_described_by_an_old_run
    write("fix_runs.json", JSON.generate("runs" => [run_record("RAILS", pid: 0)]))
    status = Operator::FixStatus.new(root: @root)
    process = { pid: Process.pid, elapsed: "00:01", queue: ["RAILS"] }

    status.stub(:processes, [process]) do
      payload = status.payload
      row = payload[:runs].last

      assert_equal "active", row[:state]
      assert_equal Process.pid, row[:pid]
      assert_equal "awaiting lifecycle receipt", row[:message]
      assert_equal "awaiting lifecycle receipt", payload[:heartbeat]
    end
  end

  def test_pre_journal_pulse_is_bound_to_a_live_pid_and_reports_staleness
    now = Time.now
    process = { pid: Process.pid, elapsed: "01:01", queue: ["RAILS"] }
    pulse = { pid: Process.pid, host: Socket.gethostname, target: "RAILS", phase: "regression baseline",
              updated_at: now.to_f - 10, phase_elapsed_s: 51, elapsed_s: 61, child_pid: 123,
              last_output_age_s: 8, checkpoints: { verified_checkpoints: 0 } }
    write("fix-live-#{Process.pid}.json", JSON.generate(pulse))
    status = Operator::FixStatus.new(root: @root, now:)
    status.stub(:processes, [process]) do
      assert_includes status.payload[:heartbeat], "phase=regression baseline"
      assert_includes status.payload[:heartbeat], "checkpoints=0"
      assert_includes status.payload[:heartbeat], "child=123"
      pulse[:updated_at] = now.to_f - 300
      write("fix-live-#{Process.pid}.json", JSON.generate(pulse))
      assert_includes status.payload[:heartbeat], "heartbeat stale"
    end
  end

  def test_status_exposes_terminal_reason_and_bounded_convergence_receipt
    run = run_record("RAILS", state: "validation_failed", pid: 0).merge(
      "message" => "validation failed:\nrendered output differs",
      "finished_at" => "2026-10-17T20:45:00Z",
      "evidence" => {
        "observations" => 3, "files_observed" => 42, "findings" => 7,
        "quality_delta" => 0.125, "finding_digest" => "a" * 64,
        "snapshot_digest" => "b" * 64, "authority_digest" => "c" * 64,
        "assessment_verification" => {
          "schema_version" => 1, "id" => "fix-assessment-proof",
          "subject" => "four-stream assessment matrix", "verifier" => "fix_assessment_matrix",
          "status" => "partial", "checked_count" => 18, "failure_count" => 2,
          "unchecked_count" => 3, "complete" => false,
        },
      },
    )
    write("fix_runs.json", JSON.generate("version" => 1, "runs" => [run]))

    status = Operator::FixStatus.new(root: @root)
    row = status.payload[:runs].first
    rendered = status.render(detail: true)

    assert_equal "validation_failed", row[:state]
    assert_equal "validation failed: rendered output differs", row[:message]
    assert_equal "2026-10-17T20:45:00Z", row[:finished]
    assert_includes row[:receipt], "observations=3"
    assert_includes row[:receipt], "files=42"
    assert_includes row[:receipt], "finding=aaaaaaaaaaaa"
    assert_includes row[:receipt], "snapshot=bbbbbbbbbbbb"
    assert_includes rendered, "fix0: validation_failed tree=RAILS pass=2/7 files=2 pid=0"
    assert_includes rendered, "result: validation failed: rendered output differs"
    assert_equal "partial", row[:assessment_verification].fetch("status")
    assert_equal 18, row[:assessment_verification].fetch("checked_count")
    assert_equal "partial incomplete checked=18 findings=2 unmeasured=3", row[:assessment_verification_summary]
    assert_includes rendered, "verification: partial incomplete checked=18 findings=2 unmeasured=3"
    assert_includes rendered, "receipt: recorded"
    assert_includes rendered, "finished: 2026-10-17T20:45:00Z"
    refute_match(/deployment validation passed/i, rendered)
  end

  def test_trees_filter_narrows_runs_logs_and_mission
    write("fix_runs.json", JSON.generate("runs" => [run_record("RAILS"), run_record("STUDIO")]))
    write_mission(JSON.generate("state" => "running", "scope" => "STUDIO"))
    write("fix-RAILS.log", "r\n")
    write("fix-STUDIO.log", "s\n")

    payload = Operator::FixStatus.new(root: @root, trees: %w[RAILS]).payload

    assert_equal %w[RAILS], payload[:runs].map { |row| row[:tree] }
    assert_equal %w[fix-RAILS.log], payload[:logs].map { |row| row[:name] }
    assert_nil payload[:mission]
  end

  def test_corrupt_journals_are_not_reported_as_empty
    write("fix_runs.json", "{not valid json")
    write_mission("{also broken")

    status = Operator::FixStatus.new(root: @root)
    payload = status.payload
    rendered = status.render

    assert_match(/invalid JSON:/, payload[:read_errors].fetch(Operator::FixStatus::JOURNAL))
    assert_match(/invalid JSON:/, payload[:read_errors].fetch(Operator::FixStatus::MISSION))
    assert_includes rendered, "unavailable (invalid JSON:"
    assert_includes rendered, "mission: unavailable (invalid JSON:"
    refute_includes rendered, "none in the journal"
    refute_match(/mission: none\z/, rendered)
  end

  def test_status_refuses_symlinked_journal_and_mission_files
    Dir.mktmpdir do |outside|
      external = File.join(outside, "payload.json")
      File.write(external, JSON.generate("version" => 1, "runs" => [run_record("RAILS")]))
      File.symlink(external, File.join(@root, "MASTER", ".master", "fix_runs.json"))
      File.symlink(external, File.join(@root, ".master", "mission.json"))

      payload = Operator::FixStatus.new(root: @root).payload

      assert_equal "refusing symlink", payload[:read_errors][Operator::FixStatus::JOURNAL]
      assert_equal "refusing symlink", payload[:read_errors][Operator::FixStatus::MISSION]
      assert_empty payload[:runs]
      assert_nil payload[:mission]
    end
  end

  def test_default_status_is_compact_and_detail_keeps_full_receipts
    run = run_record("RAILS", state: "validation_failed", pid: 0).merge(
      "message" => "validation failed: rendered output differs",
      "evidence" => {
        "observations" => 3, "files_observed" => 42, "findings" => 7,
        "assessment_verification" => {
          "schema_version" => 1, "id" => "fix-assessment-proof",
          "subject" => "four-stream assessment matrix", "verifier" => "fix_assessment_matrix",
          "status" => "partial", "checked_count" => 18, "failure_count" => 2,
          "unchecked_count" => 3, "complete" => false,
        },
      }
    )
    write("fix_runs.json", JSON.generate("version" => 1, "runs" => [run]))
    write_mission(JSON.generate("state" => "failed", "stage" => "verify", "scope" => "RAILS",
                                 "attempt_count" => 1, "artifacts" => []))

    status = Operator::FixStatus.new(root: @root)
    compact = status.render
    detailed = status.render(detail: true)
    json = JSON.parse(status.render(json: true))

    assert_includes compact, "fix0: validation_failed tree=RAILS"
    assert_includes compact, "result0: validation failed"
    assert_includes compact, "mission: failed/verify RAILS"
    assert_includes compact, "verification0: partial incomplete checked=18 findings=2 unmeasured=3"
    refute_includes compact, "assessment:"
    assert_includes detailed, "assessment:"
    assert_includes detailed, "receipt: recorded"
    assert_equal "validation_failed", json.fetch("runs").first.fetch("state")
  end

  def test_fix_tail_separates_human_log_from_global_transcript_history
    require "operator/fix_tail"
    state = File.join(@root, "MASTER", ".master", "fix_transcripts", "run-1")
    FileUtils.mkdir_p(state)
    File.write(File.join(state, "scan.ndjson"), [
      { at: "2026-11-01T10:00:00.000Z", kind: "scan", file: "a.rb" },
      { at: "2026-11-01T10:00:03.000Z", kind: "scan", file: "c.rb" },
    ].map(&:to_json).join("\n") + "\n")
    File.write(File.join(state, "repair.ndjson"), [
      { at: "2026-11-01T10:00:01.000Z", kind: "repair", file: "b.rb" },
      { at: "2026-11-01T10:00:02.000Z", kind: "repair", file: "d.rb" },
    ].map(&:to_json).join("\n") + "\n")
    File.write(File.join(@root, "MASTER", ".master", "fix-RAILS.log"), "human log\n")

    human = StringIO.new
    Operator::FixTail.run(%w[--once --tail=2], roots: [File.join(@root, "MASTER")], io: human)
    assert_equal "human log\n", human.string

    transcript = StringIO.new
    Operator::FixTail.run(%w[--once --tail=2 --transcript], roots: [File.join(@root, "MASTER")], io: transcript)

    assert_equal 2, transcript.string.lines.size
    assert_includes transcript.string, "repair: 2026-11-01T10:00:02.000Z repair"
    assert_includes transcript.string, "scan: 2026-11-01T10:00:03.000Z scan"
    refute_includes transcript.string, "human log"
  end

  def test_status_does_not_claim_delivery_when_origin_main_cannot_be_read
    status = Operator::FixStatus.new(root: @root)

    refute status.payload.fetch(:commits).fetch(:known)
    refute status.payload.fetch(:commits).fetch(:pushed)
    assert_includes status.render, "delivery: unknown (origin/main could not be read)"
  end

  def test_render_names_the_empty_cases
    text = Operator::FixStatus.new(root: @root).render

    assert_includes text, "none in the journal"
    assert_includes text, "mission: none"
  end
end
