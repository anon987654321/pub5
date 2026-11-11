# frozen_string_literal: true

require "tmpdir"
require_relative "test_helper"

# A long MASTER session runs /fix many times in one process: a file rejected twice in one run
# must be tried again by the next, while a --max-files override set for the run survives.
class TestRunLedgerPerRun < Minitest::Test
  Ledger = Master::Fix::RunLedger

  def teardown = Ledger.reset!

  def test_swallowed_error_hotspots_are_escalated_and_messages_remain_whole
    Ledger.begin_run!
    count = Master::Ground::Swallow::PLACE_BUDGET + 1
    rows = Array.new(count) do |index|
      { "context" => "Verifier.check", "error_class" => "IOError",
        "error_message" => (index == count - 1 ? "missing path /tmp/provider_health.ndjson" : "transient") }
    end

    lines = Master::Ground::Swallow.stub(:recent, ->(limit:, since:) { rows }) do
      Ledger.send(:swallowed_lines)
    end

    assert lines.any? { |line| line.include?("budget exceeded") && line.include?("Verifier.check") }
    assert lines.any? { |line| line.include?("provider_health.ndjson") }
  end

  def test_finding_docket_keeps_discoveries_attempts_and_unattempted_dispositions
    Ledger.record_discovery(file: "lib/a.rb", law: "SMALL_FILES", line: 4, message: "file too long", severity: "error")
    Ledger.record_discovery(file: "lib/a.rb", law: "SMALL_FILES", line: 8, message: "second finding", severity: "warning")
    Ledger.record_file_outcome(file: "lib/a.rb", law: "SMALL_FILES", outcome: :commit_refused, reason: "house lint")
    Ledger.record_file_outcome(file: "lib/a.rb", law: "SMALL_FILES", outcome: :applied)
    Ledger.record_discovery(file: "lib/b.rb", law: "NO_GOD_CLASS", line: 12, message: "god class", severity: "error")
    Ledger.record_disposition(file: "lib/b.rb", law: "NO_GOD_CLASS", outcome: :not_attempted_budget, reason: "stall stop")
    Ledger.record_disposition(file: "lib/b.rb", law: "NO_GOD_CLASS", outcome: :needs_person, reason: "operator-owned")

    rows = Ledger.file_outcomes
    assert_equal %w[SMALL_FILES], rows.fetch("lib/a.rb").fetch("laws")
    assert_equal 2, rows.fetch("lib/a.rb").fetch("findings").size
    assert_equal %w[commit_refused applied], rows.fetch("lib/a.rb").fetch("attempts").map { |row| row.fetch("outcome") }
    assert_equal %w[not_attempted_budget needs_person], rows.fetch("lib/b.rb").fetch("dispositions").map { |row| row.fetch("outcome") }
    lines = Ledger.file_docket_lines
    assert_includes lines.first, "2 file(s), 3 Law finding(s)"
    assert lines.any? { |line| line.include?("lib/a.rb") && line.include?("attempts=commit_refused,applied") }
    assert lines.any? { |line| line.include?("lib/b.rb") && line.include?("not_attempted_budget") && line.include?("operator-owned") }
  end

  def test_a_new_run_forgets_the_last_runs_rejections_and_keeps_its_file_cap
    2.times { Ledger.reject(:new_violations, file: "lib/a.rb") }
    Ledger.record_discovery(file: "lib/a.rb", law: "SMALL_FILES", line: 4, message: "fixture")
    Ledger.record_file_outcome(file: "lib/a.rb", law: "SMALL_FILES", outcome: :commit_refused, reason: "house lint")
    assert Ledger.file_done?("lib/a.rb")
    Ledger.max_files = 5

    Dir.mktmpdir { |root| Master::Fix::RunBudget.begin_run(root:, max_passes: 1) }

    refute Ledger.file_done?("lib/a.rb")
    assert_empty Ledger.file_outcomes, "a new run starts with an empty per-file docket"
    assert_equal 5, Ledger.max_files
  ensure
    Master::Fix::RunBudget.finish_run
  end
end
