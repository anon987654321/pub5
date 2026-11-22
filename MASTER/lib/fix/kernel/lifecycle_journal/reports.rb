# frozen_string_literal: true

module Master
  module Fix
    class Kernel
      # Assessment-report artifact lifecycle on the run journal: checksum-addressed
      # publication with read-back verification and receipt indexing, re-verification
      # of a saved receipt against its artifact, and evidence pruning.
      class LifecycleJournal
        # Persist the full Law × stream × surface ledger as an independent audit
        # artifact. The artifact write, journal receipt and reclamation share the
        # journal lock: cleanup cannot mistake an in-flight publication for an orphan.
        def persist_assessment_report(run_id, target:, report:)
          id = run_id.to_s
          raise ArgumentError, "invalid fix run id" unless id.match?(/\A[a-f0-9]{20}\z/)
          raise ArgumentError, "assessment report must be a hash" unless report.is_a?(Hash)

          with_lock { persist_assessment_report_locked!(id, target, report) }
        end

        # Re-check a saved receipt whenever a later tool needs to rely on it.
        def verify_assessment_report(run_id)
          with_lock do
            context, failure = assessment_report_receipt_context(run_id.to_s)
            return failure if failure

            artifact, failure = assessment_report_payload(context)
            return failure if failure

            document = JSON.parse(artifact[:payload])
            report, failure = assessment_report_identity(document, context)
            return failure if failure

            failure = assessment_report_provenance_failure(report, context)
            return failure if failure

            assessment_report_verified_summary(report, context, artifact)

          end
        rescue JSON::ParserError => e
          { "status" => "invalid_json", "message" => e.message.to_s[0, 180] }
        rescue StandardError => e
          { "status" => "verification_failed", "error_class" => e.class.name, "message" => e.message.to_s[0, 180] }
        end

        # Keep evidence storage aligned with the bounded run journal. A stale caller's
        # keep_ids may preserve extra files, but can never make it delete a newly indexed report.
        def prune_assessment_reports!(keep_ids:)
          with_lock do
            data = load
            retained = Array(keep_ids).map(&:to_s) |
                       Array(data["runs"]).last(MAX_RUNS).map { |entry| entry["id"].to_s }
            prune_assessment_reports_locked!(retained.to_set)
          end
        rescue StandardError => e
          emit("fix:assessment_prune_failed", error_class: e.class.name, message: e.message.to_s[0, 160])
          nil
        end

        private

        def persist_assessment_report_locked!(id, target, report)
          data = load
          run = assessment_report_run!(data, id)
          stored = write_assessment_artifact!(id, target, report)
          receipt = assessment_report_receipt(id, report, stored)
          run["assessment_receipt"] = receipt
          persist(data, run_id: id)
          emit(
            "fix:assessment_receipt_persisted",
            run_id: id, path: receipt["path"], sha256: receipt["sha256"],
            cells: receipt["cells"], readings: receipt["readings"], status: receipt["matrix_status"],
            quality_status: receipt["quality_status"], compliance_status: receipt["compliance_status"]
          )
          prune_assessment_reports_locked!(Array(data["runs"]).last(MAX_RUNS).map { |entry| entry["id"] }.to_set)
          receipt
        end

        def assessment_report_run!(data, id)
          run = Array(data["runs"]).find { |entry| entry["id"] == id }
          raise "fix run disappeared before assessment report was written" unless run

          run
        end

        def write_assessment_artifact!(id, target, report)
          assessment_dir = File.join(@state_root, ASSESSMENT_DIR)
          prepare_artifact_directory!(assessment_dir)
          path = File.join(assessment_dir, "#{id}.json")
          refuse_unsafe_artifact_slot!(path, label: "assessment report")
          payload = JSON.pretty_generate(assessment_envelope(id, target, report)) + "\n"
          write_atomic(path, payload, mode: 0o600)
          digest = verify_written_assessment_artifact!(path, payload)
          { path:, payload:, digest: }
        end

        def assessment_envelope(id, target, report)
          {
            "schema_version" => 1,
            "run_id" => id,
            "target" => relative(target),
            "created_at" => Time.now.utc.iso8601,
            "report" => json_safe_value(report),
          }
        end

        def verify_written_assessment_artifact!(path, payload)
          stored_payload = read_private_artifact(path, label: "assessment report")
          digest = Digest::SHA256.hexdigest(payload)
          raise "assessment artifact read-back mismatch" unless stored_payload == payload
          raise "assessment artifact checksum mismatch after write" unless Digest::SHA256.hexdigest(stored_payload) == digest

          digest
        end

        def assessment_report_receipt(id, report, stored)
          ledger = report[:ledger] || report["ledger"]
          summary = ledger && (ledger[:summary] || ledger["summary"])
          cells = ledger && (ledger[:cells] || ledger["cells"])
          receipt = assessment_report_receipt_base(stored, report, cells)
          assessment_report_provenance_keys(receipt, report)
          receipt["expected_cells"] = summary[:expected_cells] || summary["expected_cells"] if summary
          receipt["generation"] = summary[:generation] || summary["generation"] if summary
          receipt
        end

        def assessment_report_receipt_base(stored, report, cells)
          {
            "status" => "persisted",
            "readback_verified" => true,
            "path" => state_relative(stored[:path]),
            "sha256" => stored[:digest],
            "bytes" => stored[:payload].bytesize,
            "matrix_status" => (report[:status] || report["status"]).to_s,
            "quality_status" => assessment_report_quality_status(report, :overall_status),
            "compliance_status" => assessment_report_quality_status(report, :compliance_status),
            "cells" => Array(cells).size,
            "readings" => Array(cells).sum { |cell| Array(cell[:readings] || cell["readings"]).size },
          }
        end

        def assessment_report_quality_status(report, key)
          quality = report[:quality_contract] || report["quality_contract"] || {}
          (quality[key] || quality[key.to_s]).to_s
        end

        def assessment_report_provenance_keys(receipt, report)
          %w[plan_digest identity_digest scope_digest source_digest law_digest law_source_digest authority_digest toolchain_digest exclusion_digest adapter_digest].each do |key|
            value = report[key.to_sym] || report[key]
            receipt[key] = json_safe_value(value) unless value.nil?
          end
        end

        def assessment_report_receipt_context(id)
          return [nil, { "status" => "invalid_run_id" }] unless id.match?(/\A[a-f0-9]{20}\z/)

          assessment_dir = File.join(@state_root, ASSESSMENT_DIR)
          return [nil, { "status" => "journal_directory_symlink" }] if File.symlink?(@state_root)
          return [nil, { "status" => "assessment_directory_symlink" }] if File.symlink?(assessment_dir)

          run = history(limit: MAX_RUNS).find { |entry| entry["id"] == id }
          return [nil, { "status" => "run_not_found" }] unless run

          receipt = run["assessment_receipt"]
          return [nil, { "status" => "receipt_missing" }] unless receipt.is_a?(Hash)

          expected_path = File.join(assessment_dir, "#{id}.json")
          relative_path = state_relative(expected_path)
          return [nil, { "status" => "receipt_path_mismatch" }] unless receipt["path"] == relative_path

          [{ id:, run:, receipt:, expected_path:, relative_path: }, nil]
        end

        def assessment_report_payload(context)
          begin
            payload = read_private_artifact(context[:expected_path], label: "assessment report")
          rescue ArtifactReadError => error
            return [nil, { "status" => error.status }.merge(error.details)]
          end
          actual_digest = Digest::SHA256.hexdigest(payload)
          unless actual_digest == context[:receipt]["sha256"]
            return [nil, {
              "status" => "checksum_mismatch",
              "expected_sha256" => context[:receipt]["sha256"],
              "actual_sha256" => actual_digest,
            }]
          end
          [{ payload:, actual_digest: }, nil]
        end

        def assessment_report_identity(document, context)
          unless document["schema_version"].to_i == 1 && document["run_id"] == context[:id]
            return [nil, { "status" => "artifact_identity_mismatch" }]
          end
          return [nil, { "status" => "artifact_target_mismatch" }] unless
            document["target"].to_s == context[:run]["target"].to_s

          report = document["report"]
          return [nil, { "status" => "artifact_report_missing" }] unless report.is_a?(Hash)

          [report, nil]
        end

        def assessment_report_provenance_failure(report, context)
          failure = assessment_report_receipt_provenance_failure(report, context[:receipt])
          return failure if failure

          assessment_report_plan_provenance_failure(context[:receipt], context[:run]["plan"])
        end

        def assessment_report_receipt_provenance_failure(report, receipt)
          matrix_validation = validate_assessment_matrix_report(report)
          return matrix_validation if matrix_validation
          return { "status" => "artifact_status_mismatch" } unless
            report["status"].to_s == receipt["matrix_status"].to_s

          dimensions = %w[plan_digest identity_digest scope_digest source_digest law_digest law_source_digest authority_digest toolchain_digest exclusion_digest adapter_digest]
          dimensions.each do |key|
            expected = receipt[key]
            actual = report[key]
            next if expected.nil? && actual.nil?
            return { "status" => "provenance_mismatch", "dimension" => key } unless expected == actual
          end
          nil
        end

        def assessment_report_plan_provenance_failure(receipt, plan)
          if plan.is_a?(Hash)
            failure = assessment_report_journal_plan_mismatch(receipt, plan)
            return failure if failure
          elsif receipt["matrix_status"].to_s == "complete"
            return { "status" => "journal_plan_missing" }
          end
          assessment_report_complete_receipt_dimensions(receipt)
        end

        def assessment_report_journal_plan_mismatch(receipt, plan)
          journal_dimensions = {
            "plan_digest" => plan["digest"],
            "identity_digest" => plan["identity_digest"],
            "scope_digest" => plan["scope_digest"],
            "source_digest" => plan["source_digest"],
            "law_digest" => plan["law_digest"],
            "law_source_digest" => plan["law_source_digest"],
            "authority_digest" => plan["authority_digest"],
            "toolchain_digest" => plan["toolchain_digest"],
            "exclusion_digest" => plan["exclusion_digest"],
            "adapter_digest" => plan["adapter_digest"],
          }
          journal_dimensions.each do |key, expected|
            next if expected.nil?
            return { "status" => "journal_plan_mismatch", "dimension" => key } unless receipt[key] == expected
          end
          nil
        end

        def assessment_report_complete_receipt_dimensions(receipt)
          return unless receipt["matrix_status"].to_s == "complete"

          dimensions = %w[plan_digest identity_digest scope_digest source_digest law_digest law_source_digest authority_digest toolchain_digest exclusion_digest adapter_digest]
          missing = dimensions.select { |key| receipt[key].to_s.empty? }
          return { "status" => "receipt_provenance_incomplete", "dimensions" => missing } unless missing.empty?
        end

        def assessment_report_verified_summary(report, context, artifact)
          ledger = report["ledger"].is_a?(Hash) ? report["ledger"] : {}
          matrix_summary = ledger["summary"].is_a?(Hash) ? ledger["summary"] : {}
          cells = Array(ledger["cells"])
          surface_report = report["surface_coverage"].is_a?(Hash) ? report["surface_coverage"] : {}
          surface_rows = surface_report["surfaces"].is_a?(Hash) ? surface_report["surfaces"] : {}
          {
            "status" => "verified",
            "path" => context[:relative_path],
            "sha256" => artifact[:actual_digest],
            "bytes" => artifact[:payload].bytesize,
            "matrix_status" => context[:receipt]["matrix_status"],
            "matrix_summary" => assessment_report_matrix_summary(matrix_summary),
            "surface_coverage" => assessment_report_surface_summary(surface_report, surface_rows),
            "blockers" => assessment_report_blockers(cells),
          }
        end

        def assessment_report_matrix_summary(summary)
          {
            "laws" => summary["laws"].to_i,
            "expected_cells" => summary["expected_cells"].to_i,
            "recorded_cells" => summary["recorded_cells"].to_i,
            "pending_cells" => summary["unassessed_cells"].to_i,
            "inconclusive_cells" => summary["inconclusive_cells"].to_i,
            "finding_cells" => summary["finding_cells"].to_i,
          }
        end

        def assessment_report_surface_summary(surface_report, surface_rows)
          {
            "status" => surface_report["complete"] == true ? "complete" : "incomplete",
            "digest" => surface_report["digest"],
            "measured" => surface_rows.count { |_name, row| %w[assessed_clean not_applicable].include?(row["status"].to_s) },
            "expected" => surface_rows.size,
            "blockers" => assessment_report_surface_blockers(surface_rows),
            "surfaces" => surface_rows,
          }
        end

        def assessment_report_blockers(cells)
          cells.filter_map do |cell|
            next unless cell.is_a?(Hash)
            next unless %w[pending inconclusive violation_found opportunity_found].include?(cell["status"].to_s)

            latest = Array(cell["readings"]).last
            {
              "law" => cell["law"].to_s,
              "stream" => cell["stream"].to_s,
              "surface" => cell["surface"].to_s,
              "status" => cell["status"].to_s,
              "reason" => (latest.is_a?(Hash) ? latest["reason"] : nil).to_s.gsub(/\s+/, " ").strip[0, 180],
            }
          end.first(5)
        end

        def assessment_report_surface_blockers(surface_rows)
          surface_rows.filter_map do |name, row|
            next unless row.is_a?(Hash)
            next if %w[assessed_clean not_applicable].include?(row["status"].to_s)

            { "surface" => name, "status" => row["status"].to_s, "reason" => row["reason"].to_s[0, 180] }
          end.first(8)
        end

        def prune_assessment_reports_locked!(retained)
          directory = File.join(@state_root, ASSESSMENT_DIR)
          return 0 if File.symlink?(@state_root) || File.symlink?(directory) || !File.directory?(directory)

          removed = 0
          Dir.children(directory).each do |name|
            match = name.match(/\A([a-f0-9]{20})\.json\z/)
            next unless match && !retained.include?(match[1])

            path = File.join(directory, name)
            stat = File.lstat(path)
            next unless stat.file? && !stat.symlink? && stat.nlink == 1

            File.delete(path)
            removed += 1
          rescue SystemCallError => e
            emit("fix:assessment_prune_entry_failed", path: name, error: e.message.to_s[0, 160])
          end
          emit("fix:assessment_reports_pruned", removed:) if removed.positive?
          removed
        end
      end
    end
  end
end
