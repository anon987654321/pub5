# frozen_string_literal: true

module Master
  module Fix
    class ArchitectureExploration
      # The durable side of the architecture tournament, re-opening the class
      # defined in fix/architecture_exploration.rb: run provenance, the
      # saved-report receipt it reloads and reuses, per-tree row completion
      # checks, the aggregate report assembly and the persistence call. All
      # private; the public surface stays in fix/architecture_exploration.rb.
      private

      def provenance
        supplied = @provided_provenance.respond_to?(:to_h) ? @provided_provenance.to_h : {}
        keys = %w[
          source_digest scope_digest law_digest law_source_digest authority_digest toolchain_digest
          exclusion_digest adapter_digest identity_digest
        ]
        values = keys.to_h { |key| [key, supplied[key] || supplied[key.to_sym]] }
        values["architecture_contract_version"] = self.class.contract.fetch("version")
        values["architecture_engine_sha256"] = Digest::SHA256.file(__FILE__).hexdigest
        values["requested_candidates"] = @count
        values
      end

      def relative_target(target)
        path = File.expand_path(target.to_s, @root)
        path == @root ? "." : path.delete_prefix(@root + File::SEPARATOR)
      end

      def saved_report
        return unless @run_journal && @run_id.match?(/\A[a-f0-9]{20}\z/)

        receipt = @run_journal.verify_architecture_report(@run_id)
        return if receipt["status"] == "receipt_missing"
        unless receipt["status"] == "verified"
          @persistence_blocked = true
          raise "saved architecture report is not trustworthy: #{receipt["status"]}"
        end

        receipt["report"]
      end

      def report_matches?(report, target, current_provenance)
        report.is_a?(Hash) &&
          report["target"].to_s == relative_target(target) &&
          report["provenance"] == current_provenance
      end

      def complete_tree_row?(row)
        return false unless row.is_a?(Hash) && row["status"].to_s == "COMPLETE"
        return false unless row["requested"].to_i == @count

        requested = row["requested"].to_i
        candidates = Array(row["candidates"])
        return false unless row["accepted"].to_i == requested && candidates.size == requested

        ids = unique_candidate_ids(candidates, requested)
        return false unless ids

        qualified = candidates.select { |candidate| persisted_candidate_qualified?(candidate) }
        return false unless qualified.size == row["qualified"].to_i && qualified.size >= MIN_QUALIFIED_CANDIDATES

        winner_row_complete?(row, qualified)
      end

      # Unique candidate ids, or nil when the row's count or id uniqueness breaks.
      def unique_candidate_ids(candidates, requested)
        ids = candidates.filter_map do |candidate|
          candidate["id"].to_s if candidate.is_a?(Hash) && !candidate["id"].to_s.empty?
        end
        return unless ids.size == requested && ids.uniq.size == requested

        ids
      end

      # The winner must come from the qualified set with its shortlist entry intact.
      def winner_row_complete?(row, qualified)
        winner = row["winner"]
        return false unless winner.is_a?(Hash) && qualified.any? { |candidate| candidate["id"].to_s == winner["id"].to_s }
        return false unless winner["score"].to_i >= MIN_WINNER_SCORE
        return false unless Array(row["shortlist"]).any? { |candidate| candidate.is_a?(Hash) && candidate["id"].to_s == winner["id"].to_s }

        decision_complete?(row, qualified)
      end

      def decision_complete?(row, qualified)
        decision = row["decision"]
        return false unless decision.is_a?(Hash) && decision["selection_gate_passed"] == true
        return false unless decision["qualified_candidates"].to_i == qualified.size
        return false unless decision["execution_proof"].to_s == "NOT_RUN"

        evidence_manifest_present?(row)
      end

      # At least one manifest entry carries a path, a sha256 and a bounded excerpt.
      def evidence_manifest_present?(row)
        Array(row["evidence_manifest"]).any? do |entry|
          entry.is_a?(Hash) && !entry["path"].to_s.empty? &&
            entry["sha256"].to_s.match?(/\A[0-9a-f]{64}\z/i) &&
            entry["excerpt_bytes"].to_i.between?(1, 12_000)
        end
      end

      def persisted_candidate_qualified?(candidate)
        return false unless candidate.is_a?(Hash)

        scorecard = candidate["scorecard"]
        return false unless scorecard.is_a?(Hash)
        return false unless scorecard["total"].to_i >= MIN_WINNER_SCORE
        return false unless QUALITY_FLOORS.all? { |dimension, floor| scorecard[dimension.to_s].to_i >= floor }

        candidate["score"].to_i == scorecard["total"].to_i
      end

      def reusable_complete_report?(report, target, trees, current_provenance)
        return false unless report_matches?(report, target, current_provenance)
        return false unless report["status"] == "COMPLETE"

        by_name = Array(report["targets"]).each_with_object({}) do |row, result|
          result[row["tree"].to_s] = row if row.is_a?(Hash)
        end
        names = trees.map { |tree| File.basename(tree) }
        by_name.keys.sort == names.sort && names.all? { |name| complete_tree_row?(by_name[name]) }
      end

      def reusable_tree_rows(report, target, trees, current_provenance)
        return {} unless report_matches?(report, target, current_provenance)

        by_name = Array(report["targets"]).each_with_object({}) do |row, result|
          result[row["tree"].to_s] = row if row.is_a?(Hash) && !row["tree"].to_s.empty?
        end
        names = trees.map { |tree| File.basename(tree) }
        return {} unless (by_name.keys - names).empty?

        names.each_with_object({}) do |name, result|
          row = by_name[name]
          result[name] = row if complete_tree_row?(row)
        end
      end

      def pending_tree_row(tree)
        { "tree" => File.basename(tree), "status" => "PENDING", "requested" => @count,
          "accepted" => 0, "qualified" => 0, "decision" => nil, "winner" => nil,
          "shortlist" => [], "rejections" => [], "candidates" => [], "evidence_manifest" => [] }
      end

      def aggregate_status(rows)
        states = rows.map { |row| row.fetch("status") }
        states.all? { |value| value == "COMPLETE" } ? "COMPLETE" :
          (rows.any? { |row| row["winner"] } ? "PARTIAL" : "INCONCLUSIVE")
      end

      def aggregate_report(target:, trees:, rows:, provenance:)
        ordered = trees.map do |tree|
          row = rows[File.basename(tree)] || pending_tree_row(tree)
          row.slice(*REPORT_FIELDS)
        end
        {
          "schema_version" => 2,
          "target" => relative_target(target),
          "status" => aggregate_status(ordered),
          "provenance" => provenance,
          "requested_candidates_per_tree" => @count,
          "targets" => ordered,
          "brief" => ordered.reject { |row| row["status"] == "PENDING" }.map { |row| brief(row) }.join("\n\n"),
        }
      end

      def persist_report(target:, trees:, rows:, status:, provenance:, final_report: nil)
        return unless @run_journal && @run_id.match?(/\A[a-f0-9]{20}\z/)

        report = final_report || aggregate_report(target:, trees:, rows:, provenance:)
        report["status"] = status
        @run_journal.persist_architecture_report(@run_id, target:, report:, provenance:)
      end
    end
  end
end
