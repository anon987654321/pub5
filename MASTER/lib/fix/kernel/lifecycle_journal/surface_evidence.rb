# frozen_string_literal: true

module Master
  module Fix
    class Kernel
      # Validation of the evidence receipts nested inside an assessment report:
      # the surface-coverage snapshot (population, per-surface evidence digests,
      # completeness truth) and the opportunity pass's scope receipt.
      class LifecycleJournal
        # Surfaces a complete assessment must measure, and the states each
        # surface's evidence receipt may claim.
        SURFACE_COVERAGE_SURFACES = %w[
          repository_tree directories file_names paths cross_file media_assets compiled_assets
          rendered_ui interactive_behavior tests runtime deployment
        ].freeze
        SURFACE_EVIDENCE_STATES = %w[assessed_clean not_applicable violation_found inconclusive].freeze

        private

        def validate_surface_coverage_report(report, required:)
          surface = report["surface_coverage"]
          return { "status" => "surface_coverage_missing" } if required && !surface.is_a?(Hash)
          return unless surface.is_a?(Hash)

          failure = surface_coverage_header_failure(report, surface)
          return failure if failure

          rows = surface["surfaces"]
          details = surface["details"]
          failure = surface_coverage_population_failure(rows, details)
          return failure if failure

          failure = surface_coverage_rows_failure(rows, details)
          return failure if failure

          surface_coverage_snapshot_failure(surface, rows, details)
        rescue ArgumentError, TypeError, NoMethodError
          { "status" => "surface_coverage_malformed" }
        end

        def surface_coverage_header_failure(report, surface)
          return { "status" => "surface_coverage_schema_unsupported" } unless surface["schema_version"].to_i == 1
          return { "status" => "surface_coverage_target_mismatch" } unless surface["target_absolute"].to_s == report["target"].to_s
          %w[plan_digest source_digest].each do |key|
            return { "status" => "surface_coverage_provenance_mismatch", "dimension" => key } unless surface[key] == report[key]
          end

          nil
        end

        def surface_coverage_population_failure(rows, details)
          return { "status" => "surface_coverage_population_mismatch" } unless
            rows.is_a?(Hash) && details.is_a?(Hash) &&
            rows.keys.sort == SURFACE_COVERAGE_SURFACES.sort &&
            details.keys.sort == SURFACE_COVERAGE_SURFACES.sort

          nil
        end

        def surface_coverage_rows_failure(rows, details)
          details.each do |name, receipt|
            row = rows[name]
            return { "status" => "surface_coverage_row_malformed", "surface" => name } unless row.is_a?(Hash) && receipt.is_a?(Hash)
            status = receipt["status"].to_s
            return { "status" => "surface_coverage_state_unknown", "surface" => name } unless SURFACE_EVIDENCE_STATES.include?(status)
            evidence = receipt["evidence"] || {}
            return { "status" => "surface_coverage_evidence_malformed", "surface" => name } unless evidence.is_a?(Hash)
            evidence_sha = Digest::SHA256.hexdigest(JSON.generate(evidence))
            return { "status" => "surface_coverage_evidence_digest_mismatch", "surface" => name } unless evidence_sha == receipt["evidence_sha256"]
            %w[status reason evidence_sha256 counts].each do |key|
              expected = receipt[key]
              actual = row[key]
              next if expected.nil? && actual.nil?
              return { "status" => "surface_coverage_summary_mismatch", "surface" => name, "field" => key } unless expected == actual
            end
          end

          nil
        end

        def surface_coverage_snapshot_failure(surface, rows, details)
          inventory = surface["inventory"]
          source_manifest = surface["source_manifest"]
          snapshot_stable = surface_coverage_snapshot_stable?(inventory, source_manifest)
          return { "status" => "surface_coverage_snapshot_incomplete" } if !snapshot_stable && surface["complete"] == true

          calculated_complete = snapshot_stable && details.values.all? do |receipt|
            %w[assessed_clean not_applicable].include?(receipt["status"].to_s)
          end
          return { "status" => "surface_coverage_truth_mismatch" } unless surface["complete"] == calculated_complete

          surface_coverage_digest_failure(surface, inventory, rows)
        end

        def surface_coverage_snapshot_stable?(inventory, source_manifest)
          inventory.is_a?(Hash) && source_manifest.is_a?(Hash) &&
            inventory["status"] == "captured" && inventory["truncated"] == false &&
            source_manifest["status"] == "captured" && source_manifest["verified_after_assessment"] == true &&
            source_manifest["digest"] == source_manifest["digest_after_assessment"]
        end

        def surface_coverage_digest_failure(surface, inventory, rows)
          expected_digest = Digest::SHA256.hexdigest(JSON.generate(
            "schema_version" => surface["schema_version"],
            "target" => surface["target"],
            "plan_digest" => surface["plan_digest"],
            "source_digest" => surface["source_digest"],
            "inventory_digest" => inventory.is_a?(Hash) ? inventory["digest"] : nil,
            "surface_rows" => rows.sort.map { |name, row| [name, row["status"], row["evidence_sha256"]] },
          ))
          return { "status" => "surface_coverage_digest_mismatch" } unless surface["digest"] == expected_digest

          nil
        end

        # Validate the opportunity pass's nested scope receipt before accepting
        # any clean or positive finding from the aggregate heuristic adapter.
        def validate_opportunity_reading(report, reading)
          receipt, failure = opportunity_reading_receipt(reading)
          return failure if failure

          failure = opportunity_receipt_provenance_failure(report, receipt)
          return failure if failure

          inventory, dependencies, source_rows, failure = opportunity_receipt_manifests(receipt)
          return failure if failure

          failure = opportunity_inventory_failure(inventory)
          return failure if failure

          failure = opportunity_dependencies_failure(dependencies)
          return failure if failure

          failure = opportunity_checksum_failure(receipt, inventory, dependencies)
          return failure if failure

          failure = opportunity_sources_failure(source_rows, dependencies)
          return failure if failure

          opportunity_digest_failure(receipt, source_rows)
        rescue ArgumentError, TypeError, NoMethodError
          { "status" => "opportunity_receipt_malformed" }
        end

        def opportunity_reading_receipt(reading)
          candidates = Array(reading["evidence"]).select { |entry| entry.is_a?(Hash) }
          receipt = candidates.find do |entry|
            entry["schema_version"].to_i == 1 &&
              entry["status"].to_s == "complete"
          end
          return [nil, { "status" => "opportunity_receipt_missing" }] unless receipt

          [receipt, nil]
        end

        def opportunity_receipt_provenance_failure(report, receipt)
          return { "status" => "opportunity_receipt_provenance_mismatch" } unless
            receipt["plan_digest"] == report["plan_digest"] &&
            receipt["source_digest"] == report["source_digest"] &&
            receipt["scope_digest"] == report["scope_digest"] &&
            receipt["target"] == report["target"] &&
            receipt["source_hashes_verified"] == true &&
            receipt["snapshot_sha256"].to_s.match?(/\A[a-f0-9]{64}\z/) &&
            receipt["snapshot_sha256"] == receipt["snapshot_after_sha256"]

          nil
        end

        def opportunity_receipt_manifests(receipt)
          inventory = receipt["inventory"]
          dependencies = receipt["dependencies"]
          source_rows = receipt["source_rows"]
          unless inventory.is_a?(Array) && dependencies.is_a?(Array) && source_rows.is_a?(Array)
            return [nil, nil, nil, { "status" => "opportunity_receipt_manifest_missing" }]
          end
          unless Integer(receipt["inventory_count"]) == inventory.size &&
                 Integer(receipt["dependency_count"]) == dependencies.size &&
                 Integer(receipt["eligible_files"]) == source_rows.size
            return [nil, nil, nil, { "status" => "opportunity_receipt_count_mismatch" }]
          end

          [inventory, dependencies, source_rows, nil]
        end

        def opportunity_inventory_failure(inventory)
          inventory_valid = inventory.all? do |row|
            row.is_a?(Array) && row.size == 2 &&
              row.all? { |value| value.is_a?(String) } &&
              %w[file directory symlink other].include?(row[1])
          end
          return { "status" => "opportunity_inventory_malformed" } unless inventory_valid
          return { "status" => "opportunity_inventory_duplicate" } unless inventory.uniq.size == inventory.size

          nil
        end

        def opportunity_dependencies_failure(dependencies)
          dependencies_valid = dependencies.all? do |row|
            row.is_a?(Hash) && row["path"].is_a?(String) &&
              row["sha256"].to_s.match?(/\A[a-f0-9]{64}\z/) &&
              Integer(row["bytes"]) >= 0
          end
          return { "status" => "opportunity_dependencies_malformed" } unless dependencies_valid
          dependency_paths = dependencies.map { |row| row["path"] }
          return { "status" => "opportunity_dependency_duplicate" } unless dependency_paths.uniq.size == dependency_paths.size

          nil
        end

        def opportunity_checksum_failure(receipt, inventory, dependencies)
          inventory_digest = Digest::SHA256.hexdigest(JSON.generate(inventory))
          return { "status" => "opportunity_inventory_checksum_mismatch" } unless inventory_digest == receipt["inventory_sha256"]
          dependency_digest = Digest::SHA256.hexdigest(JSON.generate(dependencies))
          return { "status" => "opportunity_dependency_checksum_mismatch" } unless dependency_digest == receipt["dependency_sha256"]
          snapshot_digest = Digest::SHA256.hexdigest(JSON.generate([inventory_digest, dependency_digest]))
          return { "status" => "opportunity_snapshot_checksum_mismatch" } unless snapshot_digest == receipt["snapshot_sha256"]

          nil
        end

        def opportunity_sources_failure(source_rows, dependencies)
          dependencies_by_path = dependencies.to_h { |row| [row["path"], row] }
          sources_valid = source_rows.all? do |row|
            next false unless row.is_a?(Hash) && row["path"].is_a?(String)
            next false unless row["expected_sha256"].to_s.match?(/\A[a-f0-9]{64}\z/)
            next false unless row["expected_sha256"] == row["actual_sha256"]
            next false unless Integer(row["expected_bytes"]) >= 0
            next false unless row["expected_bytes"] == row["actual_bytes"]

            dependency = dependencies_by_path[row["path"]]
            dependency && dependency["sha256"] == row["actual_sha256"] &&
              dependency["bytes"] == row["actual_bytes"]
          end
          return { "status" => "opportunity_source_hash_mismatch" } unless sources_valid

          nil
        end

        def opportunity_digest_failure(receipt, source_rows)
          source_paths = source_rows.map { |row| row["path"] }
          unless source_paths.uniq.size == source_paths.size &&
                 source_paths == source_paths.sort &&
                 Digest::SHA256.hexdigest(JSON.generate(source_paths)) == receipt["scope_digest"]
            return { "status" => "opportunity_scope_digest_mismatch" }
          end
          source_manifest = source_rows.map do |row|
            [row["path"], row["expected_sha256"], Integer(row["expected_bytes"])]
          end
          unless Digest::SHA256.hexdigest(JSON.generate(source_manifest)) == receipt["source_digest"]
            return { "status" => "opportunity_source_digest_mismatch" }
          end

          nil
        end
      end
    end
  end
end
