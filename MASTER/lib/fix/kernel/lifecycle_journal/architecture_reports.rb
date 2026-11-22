# frozen_string_literal: true

module Master
  module Fix
    class Kernel
      # Architecture-tournament artifact lifecycle on the run journal: publication
      # of every accepted candidate population, receipt indexing, re-verification
      # of an indexed receipt against its artifact, and revision pruning.
      class LifecycleJournal
        # Persist every stage of the architecture tournament, including its complete accepted
        # candidate population. Keep publication, receipt indexing and pruning under
        # one lock so an unindexed in-flight revision cannot be reclaimed.
        def persist_architecture_report(run_id, target:, report:, provenance:)
          id = run_id.to_s
          raise ArgumentError, "invalid fix run id" unless id.match?(/\A[a-f0-9]{20}\z/)
          raise ArgumentError, "architecture report must be a hash" unless report.is_a?(Hash)
          raise ArgumentError, "architecture provenance must be a hash" unless provenance.is_a?(Hash)

          with_lock { persist_architecture_report_locked!(id, target, report, provenance) }
        end

        # The tournament may be resumed only from an indexed artifact whose path, permissions,
        # checksum, target, schema and provenance digest all still agree. The journal lock
        # keeps the indexed receipt and its file stable for the complete verification.
        def verify_architecture_report(run_id)
          with_lock { verify_architecture_report_locked!(run_id.to_s) }
        rescue JSON::ParserError => e
          { "status" => "invalid_json", "message" => e.message.to_s[0, 180] }
        rescue StandardError => e
          { "status" => "verification_failed", "error_class" => e.class.name, "message" => e.message.to_s[0, 180] }
        end

        # Retain only the latest indexed artifact for each retained run. Pruning
        # shares the run-journal lock with publication, receipt indexing and verification.
        def prune_architecture_reports!
          with_lock { prune_architecture_reports_locked!(load) }
        rescue StandardError => e
          emit("fix:architecture_prune_failed", error_class: e.class.name, message: e.message.to_s[0, 160])
          nil
        end

        private

        def persist_architecture_report_locked!(id, target, report, provenance)
          data = load
          run = architecture_report_run!(data, id)
          stored = write_architecture_artifact!(id, target, report, provenance)
          receipt = architecture_report_receipt(stored)
          run["architecture_receipt"] = receipt
          persist(data, run_id: id)
          emit("fix:architecture_receipt_persisted",
               run_id: id, path: receipt["path"], sha256: receipt["sha256"],
               status: receipt["report_status"], targets: receipt["target_count"],
               accepted_candidates: receipt["accepted_candidates"])
          prune_architecture_reports_locked!(data)
          receipt
        end

        def architecture_report_run!(data, id)
          run = Array(data["runs"]).find { |entry| entry["id"] == id }
          raise "fix run disappeared before architecture report was written" unless run

          run
        end

        def write_architecture_artifact!(id, target, report, provenance)
          directory = File.join(@state_root, ARCHITECTURE_DIR)
          prepare_artifact_directory!(directory)

          safe_provenance = json_safe_value(provenance)
          provenance_digest = Digest::SHA256.hexdigest(JSON.generate(safe_provenance.sort.to_h))
          revision = SecureRandom.hex(6)
          name = "#{id}-#{provenance_digest[0, 12]}-#{revision}.json"
          path = File.join(directory, name)
          refuse_unsafe_artifact_slot!(path, label: "architecture report")
          envelope, payload = architecture_envelope_payload(id, target, report, safe_provenance)
          @lifecycle_observer.mutate(operation: "persist_architecture_report",
                                     item_count: Array(envelope.dig("report", "targets")).size) do
            write_atomic(path, payload, mode: 0o600)
          end
          digest = verify_written_architecture_artifact!(path, payload)
          { path:, envelope:, payload:, digest:, provenance_digest: }
        end

        def architecture_envelope_payload(id, target, report, safe_provenance)
          envelope = {
            "schema_version" => 1,
            "run_id" => id,
            "target" => relative(target),
            "created_at" => Time.now.utc.iso8601,
            "provenance" => safe_provenance,
            "report" => json_safe_value(report),
          }
          [envelope, JSON.pretty_generate(envelope) + "\n"]
        end

        def verify_written_architecture_artifact!(path, payload)
          stored_payload = read_private_artifact(path, label: "architecture report")
          digest = Digest::SHA256.hexdigest(payload)
          raise "architecture report read-back mismatch" unless stored_payload == payload
          raise "architecture report checksum mismatch after write" unless Digest::SHA256.hexdigest(stored_payload) == digest
          file_mode = File.stat(path).mode & 0o777
          raise "architecture report permissions are not private" unless (file_mode & 0o077).zero?

          digest
        end

        def architecture_report_receipt(stored)
          targets = Array(stored[:envelope].dig("report", "targets"))
          {
            "status" => "persisted",
            "readback_verified" => true,
            "path" => state_relative(stored[:path]),
            "sha256" => stored[:digest],
            "bytes" => stored[:payload].bytesize,
            "target" => stored[:envelope]["target"],
            "report_status" => stored[:envelope].dig("report", "status").to_s,
            "target_count" => targets.size,
            "accepted_candidates" => targets.sum { |row| row.is_a?(Hash) ? row["accepted"].to_i : 0 },
            "provenance_digest" => stored[:provenance_digest][0, 12],
            "updated_at" => Time.now.utc.iso8601,
          }
        end

        def verify_architecture_report_locked!(id)
          return { "status" => "invalid_run_id" } unless id.match?(/\A[a-f0-9]{20}\z/)

          directory = File.join(@state_root, ARCHITECTURE_DIR)
          return { "status" => "journal_directory_symlink" } if File.symlink?(@state_root)
          return { "status" => "architecture_directory_symlink" } if File.symlink?(directory)

          run = history(limit: MAX_RUNS).find { |entry| entry["id"] == id }
          return { "status" => "run_not_found" } unless run
          receipt = run["architecture_receipt"]
          return { "status" => "receipt_missing" } unless receipt.is_a?(Hash)

          expected_path, match, failure = architecture_receipt_slot(id, directory, receipt)
          return failure if failure

          verify_architecture_payload!(id, receipt, run, expected_path, match)
        end

        def architecture_receipt_slot(id, directory, receipt)
          relative_path = receipt["path"].to_s
          name = File.basename(relative_path)
          match = name.match(/\A#{Regexp.escape(id)}-([a-f0-9]{12})-([a-f0-9]{12})\.json\z/)
          return [nil, nil, { "status" => "receipt_path_mismatch" }] unless match
          expected_path = File.join(directory, name)
          return [nil, nil, { "status" => "receipt_path_mismatch" }] unless state_relative(expected_path) == relative_path

          [expected_path, match, nil]
        end

        def verify_architecture_payload!(id, receipt, run, expected_path, match)
          payload, failure = architecture_artifact_payload(expected_path)
          return failure if failure

          actual_digest = Digest::SHA256.hexdigest(payload)
          return { "status" => "checksum_mismatch" } unless actual_digest == receipt["sha256"]

          envelope = JSON.parse(payload)
          failure = architecture_envelope_failure(id, receipt, run, envelope, match)
          return failure if failure

          { "status" => "verified", "path" => receipt["path"].to_s, "sha256" => actual_digest,
            "target" => envelope["target"], "provenance" => envelope["provenance"], "report" => envelope["report"] }
        end

        def architecture_artifact_payload(expected_path)
          payload = read_private_artifact(expected_path, label: "architecture report")
          [payload, nil]
        rescue ArtifactReadError => error
          [nil, { "status" => error.status }.merge(error.details)]
        end

        def architecture_envelope_failure(id, receipt, run, envelope, match)
          return { "status" => "schema_unsupported" } unless envelope["schema_version"].to_i == 1
          return { "status" => "artifact_run_mismatch" } unless envelope["run_id"] == id
          return { "status" => "target_mismatch" } unless envelope["target"] == run["target"]

          provenance = envelope["provenance"]
          return { "status" => "provenance_malformed" } unless provenance.is_a?(Hash)
          fingerprint = Digest::SHA256.hexdigest(JSON.generate(provenance.sort.to_h))
          return { "status" => "provenance_digest_mismatch" } unless fingerprint[0, 12] == match[1]
          return { "status" => "receipt_provenance_mismatch" } unless receipt["provenance_digest"] == match[1]

          report = envelope["report"]
          return { "status" => "report_malformed" } unless report.is_a?(Hash)
          return { "status" => "report_status_mismatch" } unless report["status"].to_s == receipt["report_status"].to_s
          return { "status" => "report_target_mismatch" } unless Array(report["targets"]).all? do |row|
            row.is_a?(Hash) && !row["tree"].to_s.empty?
          end

          nil
        end

        def prune_architecture_reports_locked!(data)
          directory = File.join(@state_root, ARCHITECTURE_DIR)
          return 0 if File.symlink?(@state_root) || File.symlink?(directory) || !File.directory?(directory)

          retained_paths = Array(data["runs"]).last(MAX_RUNS).filter_map do |run|
            receipt = run["architecture_receipt"]
            receipt["path"].to_s if receipt.is_a?(Hash)
          end.to_set
          removed = 0
          Dir.children(directory).each do |name|
            next unless name.match?(/\A[a-f0-9]{20}-[a-f0-9]{12}-[a-f0-9]{12}\.json\z/)

            path = File.join(directory, name)
            next if retained_paths.include?(state_relative(path))

            stat = File.lstat(path)
            next unless stat.file? && !stat.symlink? && stat.nlink == 1

            File.delete(path)
            removed += 1
          rescue SystemCallError => e
            emit("fix:architecture_prune_entry_failed", path: name, error: e.message.to_s[0, 160])
          end
          emit("fix:architecture_reports_pruned", removed:) if removed.positive?
          removed
        end
      end
    end
  end
end
