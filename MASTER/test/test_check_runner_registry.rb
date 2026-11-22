# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "yaml"
require "open3"
require "rbconfig"

class TestCheckRunnerRegistry < Minitest::Test
  MASTER_ROOT = File.expand_path("..", __dir__)
  REPOSITORY_ROOT = File.expand_path("../..", __dir__)
  RUNNER = File.join(MASTER_ROOT, "checks", "runner.rb")

  def run_registry(registry)
    Dir.mktmpdir("check-registry-contract") do |dir|
      registry_path = File.join(dir, "checks.yml")
      ledger_path = File.join(dir, "ledger.jsonl")
      File.write(registry_path, YAML.dump(registry))
      output, status = Open3.capture2e(
        { "CHECKS_FILE" => registry_path, "CHECK_LEDGER" => ledger_path,
          "CHECK_AUTOFIX" => "0" },
        RbConfig.ruby, RUNNER, "--all", chdir: REPOSITORY_ROOT
      )
      yield output, status, ledger_path
    end
  end

  def test_failed_script_reports_a_bounded_redacted_output_excerpt
    fixture = File.join(File.dirname(RUNNER), "diagnostic-#{Process.pid}.rb")
    File.write(fixture, <<~RUBY)
      puts "first diagnostic line"
      warn "provider returned API_KEY=sk-abcdefghijklmnopqrstuvwxyz123456"
      warn "Authorization: Bearer ghp_abcdefghijklmnopqrstuvwxyz123456"
      warn "Authorization: Basic Zm9vOnNlY3JldA=="
      warn "Cookie: session=session-secret; csrf=csrf-secret"
      warn "request https://user:supersecret@example.test/a?token=query-secret"
      warn "last diagnostic line"
      exit 7
    RUBY

    run_registry("diagnostic" => { "script" => File.basename(fixture) }) do |output, status, ledger_path|
      refute status.success?
      assert_includes output, "diagnostic-#{Process.pid}.rb exited 7"
      assert_includes output, "last diagnostic line"
      assert_includes output, "API_KEY=[redacted]"
      assert_includes output, "Authorization: [redacted]"
      assert_includes output, "Cookie: [redacted]"
      refute_includes output, "sk-abcdefghijklmnopqrstuvwxyz123456"
      refute_includes output, "ghp_abcdefghijklmnopqrstuvwxyz123456"
      refute_includes output, "Zm9vOnNlY3JldA=="
      refute_includes output, "session-secret"
      refute_includes output, "csrf-secret"
      refute_includes output, "supersecret"
      refute_includes output, "query-secret"

      private_log = File.read(File.join(File.dirname(ledger_path), ".check_output.log"))
      assert_includes private_log, "API_KEY=[redacted]"
      assert_includes private_log, "Authorization: [redacted]"
      assert_includes private_log, "Cookie: [redacted]"
      refute_includes private_log, "sk-abcdefghijklmnopqrstuvwxyz123456"
      refute_includes private_log, "ghp_abcdefghijklmnopqrstuvwxyz123456"
      refute_includes private_log, "Zm9vOnNlY3JldA=="
      refute_includes private_log, "session-secret"
      refute_includes private_log, "csrf-secret"
      refute_includes private_log, "supersecret"
      refute_includes private_log, "query-secret",
                      "the on-disk diagnostics log must receive the same redaction as terminal output"
    end
  ensure
    File.delete(fixture) if fixture && File.file?(fixture)
  end
  def test_registry_rejects_rows_that_declare_both_class_and_script
    run_registry(
      "ambiguous" => { "class" => "Deploy::CheckResult", "script" => "architecture.rb" },
    ) do |output, status|
      refute status.success?
      assert_includes output, "must declare exactly one of class: or script:"
    end
  end

  def test_registry_rejects_blank_class_with_script
    run_registry("blank_class" => { "class" => " ", "script" => "architecture.rb" }) do |output, status|
      refute status.success?
      assert_includes output, "class:/script: must be a non-empty string when declared"
    end
  end

  def test_registry_rejects_blank_script_with_class
    run_registry("blank_script" => { "class" => "Deploy::CheckResult", "script" => "" }) do |output, status|
      refute status.success?
      assert_includes output, "class:/script: must be a non-empty string when declared"
    end
  end

  def test_registry_rejects_script_paths_that_escape_checks_tree
    run_registry("bad_script" => { "script" => "../README.md" }) do |output, status|
      refute status.success?
      assert_includes output, "script: parent or absolute paths are not allowed"
    end
  end

  def test_registry_rejects_require_paths_that_escape_declared_tree
    run_registry(
      "bad_require" => { "require" => "../../README.md", "class" => "Deploy::CheckResult" },
    ) do |output, status|
      refute status.success?
      assert_includes output, "require: parent or absolute paths are not allowed"
    end
  end

  def test_registry_rejects_rows_without_an_execution_mechanism
    run_registry("missing_executor" => { "require" => "fixtures/failopen/checks_fixture" }) do |output, status|
      refute status.success?
      assert_includes output, "must declare exactly one of class: or script:"
    end
  end

  def test_registry_rejects_missing_script_files
    run_registry("missing_script" => { "script" => "no_such_check.rb" }) do |output, status|
      refute status.success?
      assert_includes output, "script: path does not identify an existing file"
    end
  end

  def test_registry_rejects_missing_require_files
    run_registry(
      "missing_require" => { "require" => "lib/no_such_check", "class" => "Deploy::NoSuchCheck" },
    ) do |output, status|
      refute status.success?
      assert_includes output, "require: path does not identify an existing file"
    end
  end

  def test_registry_rejects_absolute_script_paths
    run_registry("bad_script" => { "script" => File.join(Dir.tmpdir, "arbitrary.rb") }) do |output, status|
      refute status.success?
      assert_includes output, "script: parent or absolute paths are not allowed"
    end
  end
end
