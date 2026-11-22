# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
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
      main_sha: "a".repeat(40), main_ref: "refs/heads/main",
      checked_out_sha: "b".repeat(40), clean_checkout: true,
      environment: "ruby 3.4.0"
    }

    log_artifact = {
      "path" => ".master/check/latest.log",
      "byte_count" => 17,
      "sha256" => "a" * 64,
    }
    json = Operator::CheckBrief.render_json(
      profile: "focused", results: [result], metadata:,
      started_at: "2026-11-22T12:00:00.000Z",
      finished_at: "2026-11-22T12:00:01.300Z",
      duration_s: 1.3, exit_status: 0,
      command: "MASTER/bin/check --profile=focused --format=json",
      log_path: ".master/check/latest.log", log_artifact:
    )
    receipt = JSON.parse(json)

    assert_equal 1, receipt.fetch("schema_version")
    assert_equal "master_check", receipt.fetch("receipt_type")
    assert_equal "PASS", receipt.fetch("status")
    assert_match(/\A[0-9a-f-]{36}\z/, receipt.fetch("receipt_id"))
    assert_match(/\A[0-9a-f-]{36}\z/, receipt.fetch("operation_id"))
    assert_equal "check", receipt.fetch("operation_type")
    assert_equal "a" * 40, receipt.fetch("exact_main_sha")
    assert_equal "b" * 40, receipt.fetch("exact_checked_out_sha")
    assert_equal true, receipt.fetch("clean_checkout")
    assert_equal true, receipt.fetch("repository_evidence_complete")
    assert_equal 1, receipt.dig("counts", "passed")
    assert_equal 1_250, receipt.dig("steps", 0, "duration_ms")
    assert_equal 0, receipt.dig("steps", 0, "exit_status")
    assert_equal "bundle exec rake test:core", receipt.dig("steps", 0, "command")
    assert_nil receipt.fetch("test_counts")
    assert_nil receipt.fetch("receipt_path")
    assert_equal "stdout", receipt.fetch("receipt_output")
    refute_includes json, "do-not-publish-this-output"
    assert_equal false, receipt.dig("evidence", "raw_output_included")
    assert_equal log_artifact, receipt.dig("evidence", "combined_log_artifact")
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

    nested_timeout = Operator::CheckRunner::Result.new(
      name: "all tree suites", success: false, output: "nested child timeout",
      timed_out: false, exit_status: 124, command: "rake test:all_trees"
    )
    nested = JSON.parse(Operator::CheckBrief.render_json(
      profile: "full", results: [nested_timeout], metadata:,
      started_at: "start", finished_at: "finish", duration_s: 8,
      exit_status: 1, command: "MASTER/bin/check --profile=full --format=json"
    ))
    assert_equal "TIMEOUT", nested.fetch("status")
    assert_equal "TIMEOUT", nested.dig("steps", 0, "status")
    assert_equal 1, nested.dig("counts", "timed_out")

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

    measured_nothing = Operator::CheckRunner::Result.new(
      name: "all tree tests", success: false, output: "Node.js unavailable",
      timed_out: false, exit_status: 3, command: "rake test:all_trees"
    )
    inconclusive = JSON.parse(Operator::CheckBrief.render_json(
      profile: "full", results: [measured_nothing], metadata:,
      started_at: "start", finished_at: "finish", duration_s: 3,
      exit_status: 1, command: "MASTER/bin/check --profile=full --format=json"
    ))
    assert_equal "INCONCLUSIVE", inconclusive.fetch("status")
    assert_equal "INCONCLUSIVE", inconclusive.dig("steps", 0, "status")
    assert_equal 1, inconclusive.dig("counts", "inconclusive")

    dirty = JSON.parse(Operator::CheckBrief.render_json(
      profile: "agent", results: [Operator::CheckRunner::Result.new(
        name: "law syntax", success: true, output: "ok",
        started_at: "start", finished_at: "finish", elapsed_s: 1,
        exit_status: 0, command: "ruby -c"
      )], metadata: metadata.merge(main_sha: "a" * 40, checked_out_sha: "b" * 40,
                                   branch: "main", main_ref: "refs/heads/main",
                                   clean_checkout: false),
      started_at: "start", finished_at: "finish", duration_s: 1,
      exit_status: 0, command: "MASTER/bin/check --profile=agent --format=json"
    ))
    assert_equal "INCONCLUSIVE", dirty.fetch("status")
    assert_equal false, dirty.fetch("repository_evidence_complete")
  end

  def test_file_evidence_is_bounded_and_refuses_links_or_escape
    Dir.mktmpdir("check-log-evidence") do |root|
      log = File.join(root, ".master", "check", "latest.log")
      FileUtils.mkdir_p(File.dirname(log))
      bytes = "private check output\n"
      File.binwrite(log, bytes)

      evidence = Operator::CheckBrief.file_evidence(root:, path: log)

      assert_equal ".master/check/latest.log", evidence.fetch("path")
      assert_equal bytes.bytesize, evidence.fetch("byte_count")
      assert_equal Digest::SHA256.hexdigest(bytes), evidence.fetch("sha256")
      refute_includes evidence.to_s, bytes

      assert_raises(ArgumentError) do
        Operator::CheckBrief.file_evidence(root:, path: File.join(root, "..", "outside.log"))
      end

      symlink = File.join(File.dirname(log), "symlink.log")
      File.symlink(log, symlink)
      assert_raises(IOError) do
        Operator::CheckBrief.file_evidence(root:, path: symlink)
      end

      hardlink = File.join(File.dirname(log), "hardlink.log")
      File.link(log, hardlink)
      assert_raises(IOError) do
        Operator::CheckBrief.file_evidence(root:, path: hardlink)
      end
    end
  end

  def test_write_json_receipt_persists_atomically_with_private_permissions
    Dir.mktmpdir("check-receipt") do |root|
      receipt_id = SecureRandom.uuid
      relative = ".master/check/receipts/#{receipt_id}.json"
      receipt = {
        "schema_version" => 1,
        "receipt_id" => receipt_id,
        "receipt_path" => relative,
        "receipt_output" => "stdout+file",
        "status" => "PASS",
      }

      path = Operator::CheckBrief.write_json_receipt(root:, receipt:)

      assert_equal File.join(root, relative), path
      assert File.file?(path)
      assert_equal receipt, JSON.parse(File.read(path))
      assert_equal 0o600, File.stat(path).mode & 0o777
      assert File.binread(path).end_with?("\n")
    end
  end

  def test_write_json_receipt_rejects_invalid_identity_and_path_substitution
    Dir.mktmpdir("check-receipt") do |root|
      valid_id = SecureRandom.uuid
      valid_path = ".master/check/receipts/#{valid_id}.json"

      invalid_id = { "receipt_id" => "../escape", "receipt_path" => valid_path }
      assert_raises(ArgumentError) do
        Operator::CheckBrief.write_json_receipt(root:, receipt: invalid_id)
      end

      mismatched_path = { "receipt_id" => valid_id, "receipt_path" => "../escape.json" }
      assert_raises(ArgumentError) do
        Operator::CheckBrief.write_json_receipt(root:, receipt: mismatched_path)
      end

      refute File.exist?(File.join(root, "escape.json"))
      refute File.exist?(File.join(root, ".master", "check", "receipts", "#{valid_id}.json"))

      existing = File.join(root, valid_path)
      FileUtils.mkdir_p(File.dirname(existing))
      File.binwrite(existing, "operator-owned receipt\n")
      assert_raises(Errno::EEXIST) do
        Operator::CheckBrief.write_json_receipt(
          root:, receipt: { "receipt_id" => valid_id, "receipt_path" => valid_path }
        )
      end
      assert_equal "operator-owned receipt\n", File.binread(existing)
    end
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
