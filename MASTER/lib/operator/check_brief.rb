# frozen_string_literal: true

require "json"
require "securerandom"
require "digest"
require_relative "../io/atomic_write"

module Operator
  module CheckBrief
    HINTS = {
      "selftest" => {
        category: "known_debt",
        debt_tag: "agent-ignore",
        suggested_action: "skip unless the task targets scan rules",
      },
      "lint:data_singularity" => {
        category: "true_violation",
        debt_tag: nil,
        suggested_action: "fix YAML alias/duplicate keys or restore shard singularity",
      },
      "test:core" => {
        category: "true_violation",
        debt_tag: nil,
        suggested_action: "fix core/ fold spine regression; run rake test:core",
      },
      "test" => {
        category: "true_violation",
        debt_tag: nil,
        suggested_action: "fix failing unit test or revert behavioral change",
      },
      "spec" => {
        category: "true_violation",
        debt_tag: nil,
        suggested_action: "fix failing spec or revert behavioral change",
      },
      "security_sweep" => {
        category: "true_violation",
        debt_tag: nil,
        suggested_action: "resolve security sweep finding before merge",
      },
      "web ui static" => {
        category: "true_violation",
        debt_tag: nil,
        suggested_action: "fix web UI static check; see data/agent_map.yml topics.face_boot",
      },
      "test:web" => {
        category: "true_violation",
        debt_tag: nil,
        suggested_action: "fix live web test (MASTER_WEB_LIVE=1)",
      },
      "test:integration_web" => {
        category: "true_violation",
        debt_tag: nil,
        suggested_action: "fix integration web test (MASTER_WEB_LIVE=1)",
      },
      "bin/ci" => {
        category: "operator_check",
        debt_tag: "operator-priority",
        suggested_action: "run bin/ci locally and fix first failure class",
      },
      "bin/probe all" => {
        category: "operator_check",
        debt_tag: "operator-priority",
        suggested_action: "run bin/probe all and fix readiness matrix gap",
      },
      "audit" => {
        category: "operator_check",
        debt_tag: "operator-priority",
        suggested_action: "resolve rake audit finding",
      },
    }.freeze

    module_function

    def hint_for(step_name)
      key = step_name.to_s.strip
      return HINTS[key] if HINTS.key?(key)

      # The longest matching prefix wins, so test:web_ui takes test:web and not test.
      pattern = HINTS.keys.select { |prefix| key.start_with?(prefix) }.max_by(&:length)
      return HINTS[pattern] if pattern

      {
        category: "unknown",
        debt_tag: nil,
        suggested_action: "read step output; rerun with CHECK_VERBOSE=1",
      }
    end

    def render(profile:, results:)
      total = results.size
      passed = results.count(&:success)
      failed = results.reject(&:success)
      lines = ["profile: #{profile}", "status: #{failed.empty? ? 'clean' : 'fail'}", "checks_passed: #{passed}/#{total}"]

      return lines.join("\n") if failed.empty?

      first = failed.first
      hint = hint_for(first.name)
      lines << "first_failure: #{first.name}"
      lines << "category: #{hint[:category]}"
      lines << "debt_tag: #{hint[:debt_tag]}" if hint[:debt_tag]
      lines << "suggested_action: #{hint[:suggested_action]}"
      lines << "checks_remaining: #{failed.size}/#{total}"
      snippet = output_snippet(first.output)
      lines << "output_snippet: #{snippet}" if snippet
      lines.join("\n")
    end

    # A machine-readable projection of the exact steps this invocation ran.
    # It deliberately omits command output and environment values: logs remain
    # the bounded human diagnostic, while this receipt carries status evidence.
    def render_json(profile:, results:, metadata:, started_at:, finished_at:,
                    duration_s:, exit_status:, command:, log_path: nil,
                    receipt_id: SecureRandom.uuid, operation_id: SecureRandom.uuid,
                    receipt_path: nil, receipt_persisted: false,
                    log_artifact: nil)
      step_rows = results.map do |result|
        {
          "name" => result.name.to_s,
          "status" => step_status(result),
          "started_at" => result.started_at,
          "finished_at" => result.finished_at,
          "duration_ms" => result.elapsed_s && (result.elapsed_s * 1000).round,
          "exit_status" => result.exit_status,
          "signal" => result.signal,
          "command" => result.command,
        }
      end
      statuses = step_rows.map { |row| row.fetch("status") }
      passed = statuses.count("PASS")
      failed = statuses.count("FAIL")
      timed_out = statuses.count("TIMEOUT")
      blocked = statuses.count("BLOCKED")
      inconclusive = statuses.count("INCONCLUSIVE")
      repository_evidence_complete = metadata[:main_sha].to_s.match?(/\A[0-9a-f]{40}\z/i) &&
                                     metadata[:checked_out_sha].to_s.match?(/\A[0-9a-f]{40}\z/i) &&
                                     !metadata[:branch].to_s.empty? &&
                                     metadata[:clean_checkout] == true &&
                                     !metadata[:main_ref].to_s.empty?
      status = if failed.positive?
                 "FAIL"
               elsif timed_out.positive?
                 "TIMEOUT"
               elsif blocked.positive?
                 "BLOCKED"
               elsif inconclusive.positive?
                 "INCONCLUSIVE"
               elsif statuses.empty?
                 "NOT_RUN"
               elsif !repository_evidence_complete
                 "INCONCLUSIVE"
               else
                 "PASS"
               end

      receipt = {
        "schema_version" => 1,
        "receipt_id" => receipt_id,
        "operation_id" => operation_id,
        "operation_type" => "check",
        "receipt_type" => "master_check",
        "profile" => profile.to_s,
        "status" => status,
        "started_at" => started_at,
        "finished_at" => finished_at,
        "duration_ms" => (duration_s.to_f * 1000).round,
        "repository" => metadata[:repository],
        "branch" => metadata[:branch],
        "exact_main_sha" => metadata[:main_sha],
        "main_ref" => metadata[:main_ref],
        "exact_checked_out_sha" => metadata[:checked_out_sha],
        "clean_checkout" => metadata[:clean_checkout],
        "repository_evidence_complete" => repository_evidence_complete,
        "environment" => metadata[:environment],
        "command" => command,
        "exit_status" => (statuses.empty? ? nil : exit_status),
        "counts" => {
          "steps" => statuses.size,
          "passed" => passed,
          "failed" => failed,
          "timed_out" => timed_out,
          "blocked" => blocked,
          "inconclusive" => inconclusive,
        },
        "test_counts" => nil,
        "receipt_path" => receipt_path,
        "receipt_output" => (receipt_persisted ? "stdout+file" : "stdout"),
        "steps" => step_rows,
        "evidence" => {
          "combined_log" => log_path,
          "combined_log_artifact" => log_artifact,
          "receipt_persisted" => receipt_persisted,
          "raw_output_included" => false,
        },
      }
      JSON.pretty_generate(receipt) << "\n"
    end

    # Hash a private local artifact without copying its body into the receipt.
    # Paths are confined to the repository and must name a singly-linked file.
    def file_evidence(root:, path:)
      return unless path

      expanded_root = File.expand_path(root)
      expanded_path = File.expand_path(path, expanded_root)
      prefix = expanded_root + File::SEPARATOR
      raise ArgumentError, "artifact path escapes repository" unless expanded_path.start_with?(prefix)

      stat = File.lstat(expanded_path)
      unless stat.file? && !stat.symlink? && stat.nlink == 1
        raise IOError, "artifact must be a singly-linked regular file"
      end

      {
        "path" => expanded_path.delete_prefix(prefix),
        "byte_count" => stat.size,
        "sha256" => Digest::SHA256.file(expanded_path).hexdigest,
      }
    end

    # Persist one immutable check receipt beneath the private runtime area.
    # The caller supplies only the UUID identity; paths never come from input.
    def write_json_receipt(root:, receipt:)
      receipt_id = receipt.fetch("receipt_id").to_s
      uuid = /\A[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}\z/i
      raise ArgumentError, "invalid receipt ID" unless receipt_id.match?(uuid)

      expected = ".master/check/receipts/#{receipt_id}.json"
      raise ArgumentError, "receipt path does not match its ID" unless receipt.fetch("receipt_path") == expected

      destination = File.join(File.expand_path(root), expected)
      raise Errno::EEXIST, destination if File.exist?(destination) || File.symlink?(destination)

      Master::Io::AtomicWrite.write_atomic(destination, JSON.pretty_generate(receipt) << "\n", mode: 0o600)
      destination
    end

    def step_status(result)
      return "TIMEOUT" if (result.respond_to?(:timed_out) && result.timed_out) || result.exit_status == 124
      return "PASS" if result.success
      return "BLOCKED" if result.name.to_s.match?(/\bunavailable\b/i)
      return "INCONCLUSIVE" if result.exit_status == 3

      "FAIL"
    end

    def output_snippet(output)
      line = output.to_s.lines.map(&:strip).reject(&:empty?).find { |l| !l.start_with?("check:") }
      return unless line

      line.length > 120 ? "#{line[0, 117]}..." : line
    end
  end
end
