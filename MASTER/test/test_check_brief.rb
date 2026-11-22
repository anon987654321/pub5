# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/operator/check_brief"
require_relative "../lib/operator/check_runner"

class TestCheckBrief < Minitest::Test
  def test_selftest_hint_is_known_debt
    hint = Operator::CheckBrief.hint_for("selftest")
    assert_equal "known_debt", hint[:category]
    assert_equal "agent-ignore", hint[:debt_tag]
  end

  def test_render_clean
    results = [
      Operator::CheckRunner::Result.new(name: "lint:data_singularity", success: true, output: ""),
    ]
    output = Operator::CheckBrief.render(profile: "agent", results:)
    assert_includes output, "status: clean"
    assert_includes output, "checks_passed: 1/1"
  end

  def test_render_json_includes_step_evidence_without_raw_output
    result = Operator::CheckRunner::Result.new(
      name: "test:core", success: true, output: "do-not-publish-this-output",
      started_at: "2026-11-22T12:00:00.000Z",
      finished_at: "2026-11-22T12:00:01.250Z",
      elapsed_s: 1.25, exit_status: 0, signal: nil,
      timed_out: false, command: "bundle exec rake test:core"
    )
    metadata = {
      repository: "anon987654321/pub5", branch: "main",
      main_sha: "abc123", main_ref: "refs/heads/main",
      checked_out_sha: "abc123", clean_checkout: true,
      environment: "ruby 3.4.0"
    }

    json = Operator::CheckBrief.render_json(
      profile: "focused", results: [result], metadata:,
      started_at: "2026-11-22T12:00:00.000Z",
      finished_at: "2026-11-22T12:00:01.300Z",
      duration_s: 1.3, exit_status: 0,
      command: "MASTER/bin/check --profile=focused --format=json",
      log_path: ".master/check/latest.log"
    )
    receipt = JSON.parse(json)

    assert_equal 1, receipt.fetch("schema_version")
    assert_equal "master_check", receipt.fetch("receipt_type")
    assert_equal "PASS", receipt.fetch("status")
    assert_match(/\A[0-9a-f-]{36}\z/, receipt.fetch("receipt_id"))
    assert_equal "check", receipt.fetch("operation_type")
    assert_equal "abc123", receipt.fetch("exact_main_sha")
    assert_equal "abc123", receipt.fetch("exact_checked_out_sha")
    assert_equal true, receipt.fetch("clean_checkout")
    assert_equal 1, receipt.dig("counts", "passed")
    assert_equal 1_250, receipt.dig("steps", 0, "duration_ms")
    assert_equal 0, receipt.dig("steps", 0, "exit_status")
    assert_equal "bundle exec rake test:core", receipt.dig("steps", 0, "command")
    assert_nil receipt.fetch("test_counts")
    refute_includes json, "do-not-publish-this-output"
    assert_equal false, receipt.dig("evidence", "raw_output_included")
  end

  def test_render_json_preserves_timeout_failure_and_not_run_states
    result = Operator::CheckRunner::Result.new(
      name: "web ui behaviour unavailable", success: false,
      output: "private diagnostic", timed_out: true
    )
    metadata = { repository: "pub5", clean_checkout: nil }

    timeout = JSON.parse(Operator::CheckBrief.render_json(
      profile: "web", results: [result], metadata:,
      started_at: "start", finished_at: "finish", duration_s: 4,
      exit_status: 1, command: "MASTER/bin/check --profile=web --format=json"
    ))
    assert_equal "TIMEOUT", timeout.fetch("status")
    assert_equal "TIMEOUT", timeout.dig("steps", 0, "status")
    assert_equal 1, timeout.dig("counts", "timed_out")

    failure = Operator::CheckRunner::Result.new(
      name: "security_sweep", success: false, output: "not included",
      timed_out: false, exit_status: 1, command: "rake security_sweep"
    )
    mixed = JSON.parse(Operator::CheckBrief.render_json(
      profile: "operator", results: [result, failure], metadata:,
      started_at: "start", finished_at: "finish", duration_s: 5,
      exit_status: 1, command: "MASTER/bin/check --profile=operator --format=json"
    ))
    assert_equal "FAIL", mixed.fetch("status")
    assert_equal 1, mixed.dig("counts", "failed")
    assert_equal 1, mixed.dig("counts", "timed_out")
    refute_includes mixed.to_s, "private diagnostic"

    empty = JSON.parse(Operator::CheckBrief.render_json(
      profile: "agent", results: [], metadata:,
      started_at: "start", finished_at: "finish", duration_s: 0,
      exit_status: 0, command: "MASTER/bin/check --profile=agent --format=json"
    ))
    assert_equal "NOT_RUN", empty.fetch("status")
    assert_equal 0, empty.dig("counts", "steps")
    assert_nil empty.fetch("exit_status")

    unavailable = Operator::CheckRunner::Result.new(
      name: "web ui behaviour unavailable", success: false,
      output: "not measured", timed_out: false, exit_status: 3,
      command: "ruby -e unavailable"
    )
    blocked = JSON.parse(Operator::CheckBrief.render_json(
      profile: "web", results: [unavailable], metadata:,
      started_at: "start", finished_at: "finish", duration_s: 1,
      exit_status: 1, command: "MASTER/bin/check --profile=web --format=json"
    ))
    assert_equal "BLOCKED", blocked.fetch("status")
    assert_equal 1, blocked.dig("counts", "blocked")
  end

  def test_render_failure
    results = [
      Operator::CheckRunner::Result.new(name: "selftest", success: false, output: "ROBUSTNESS: lib/foo.rb\n"),
      Operator::CheckRunner::Result.new(name: "lint:data_singularity", success: true, output: ""),
    ]
    output = Operator::CheckBrief.render(profile: "agent", results:)
    assert_includes output, "status: fail"
    assert_includes output, "first_failure: selftest"
    assert_includes output, "category: known_debt"
    assert_includes output, "debt_tag: agent-ignore"
    assert_includes output, "checks_remaining: 1/2"
  end
end
