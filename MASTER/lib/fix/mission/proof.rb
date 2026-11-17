# frozen_string_literal: true

module Master
  module Fix
    class Mission
      # Durable receipts, re-opening the class defined in fix/mission.rb: the
      # proof record an attempt leaves behind, the stricter /fix-pipeline
      # proof with its command evidence, and the per-file repository write
      # receipt that lets a later attempt prove its edits survived.
      def record_proof!(proof:)
        receipt = proof_receipt(proof.is_a?(Hash) ? proof : {})
        return false unless receipt["proved"] || receipt["answerable"]

        with_lock do
          load_writable_unlocked!
          return false unless @record

          @record["proof"] = receipt
          @record["last_seen_at"] = now
          persist!
        end
        emit("mission:proof", id: @id, proved: receipt["proved"], answerable: receipt["answerable"],
                             evidence_score: receipt["evidence_score"], write_paths: receipt["write_paths"].size)
        true
      rescue ArgumentError, TypeError
        false
      end

      def record_fix_proof!(status:, scope_paths:, report:, command_proof:)
        text = report.to_s
        return false unless passing_fix_report?(status, text)

        paths = safe_scope_paths(scope_paths)
        return false unless paths

        line = text.lines.find { |entry| entry.match?(/fix done/i) && entry.match?(/proof:/i) }.to_s.strip
        with_lock do
          return false unless store_fix_proof!(paths, text, line, command_proof)
        end
        emit("mission:proof", id: @id, source: "fix_pipeline", status: "pass", scope_paths: paths.size)
        true
      rescue ArgumentError, TypeError, JSON::ParserError, KeyError, NoMethodError
        false
      end

      def record_repository_write!(path:, content:, repository_root:)
        repo = File.realpath(repository_root)
        receipt = verified_repository_write(path, content, repo)
        return false unless receipt

        relative, digest = receipt
        with_lock do
          return false unless store_repository_write!(repo, relative, digest)
        end
        emit("mission:write_receipt", id: @id, path: relative, digest:)
        true
      rescue SystemCallError, ArgumentError => error
        emit("mission:write_receipt_refused", id: @id, reason: error.class.name)
        false
      end

      private

      def proof_receipt(source)
        value = lambda do |key|
          source.key?(key) ? source[key] : source[key.to_s]
        end
        paths = lambda do |key|
          Array(value.call(key)).map(&:to_s).uniq.select do |path|
            !path.empty? && !Pathname.new(path).absolute? && !path.split("/").include?("..")
          end.first(128)
        end
        {
          "proved" => value.call(:proved) == true,
          "answerable" => value.call(:answerable) == true,
          "evidence_score" => Integer(value.call(:evidence) || 0),
          "repository_delivery" => value.call(:repository_delivery) == true,
          "write_paths" => paths.call(:write_paths),
          "delivery_paths" => paths.call(:delivery_paths),
          "council_cleared" => value.call(:cleared) == true,
          "ideation_satisfied" => value.call(:writable) == true,
          "generation" => Integer(value.call(:generation) || 0),
          "write_lines" => Integer(value.call(:write_lines) || 0),
        }
      end

      def passing_fix_report?(status, text)
        return false unless status.to_s == "pass"
        return false unless text.match?(/\bfix done\b/i)
        return false unless text.match?(/\bproof:\s*(?!\s*no proof ran\b)/i)
        return false unless text.match?(/hard red 0\b/i)
        return false if text.match?(/unmeasured [1-9]\d*\b/i)
        return false if text.match?(/review\d+:\s*(?:incomplete|complete with open findings)\b/i)

        true
      end

      def safe_scope_paths(scope_paths)
        paths = Array(scope_paths).map(&:to_s).uniq
        return if paths.empty? || paths.size > 128
        return unless paths.all? do |path|
          !path.empty? && !Pathname.new(path).absolute? && !path.split("/").include?("..")
        end

        paths
      end

      def store_fix_proof!(paths, text, line, command_proof)
        plan, required = fix_proof_plan
        return unless plan

        evidence = command_proof.to_h.transform_keys(&:to_s)
        command_evidence = valid_command_evidence(plan, required, evidence)
        return unless command_evidence

        @record["proof"] = {
          "kind" => "fix_pipeline",
          "status" => "pass",
          "scope_paths" => paths,
          "report_digest" => Digest::SHA256.hexdigest(text),
          "proof_summary" => line.byteslice(0, 512),
          "proof_map_version" => plan.fetch("proof_map_version"),
          "required_proof_types" => required,
          "command_evidence" => command_evidence,
        }
        @record["last_seen_at"] = now
        persist!
        true
      end

      def fix_proof_plan
        load_writable_unlocked!
        return unless @record && @record["origin"].to_s == "backlog"

        plan = JSON.parse(@record["plan"].to_s)
        required = Array(plan["proof_types"]).map(&:to_s)
        allowed = TaskContract.template.fetch("proof_types").map(&:to_s)
        map_version = Backlog::ProofMap::VERSION if defined?(Backlog::ProofMap::VERSION)
        return unless plan["executor"] == "root_todo" && plan["proof_map_version"] == map_version
        return if required.empty? || required.uniq != required || (required - allowed).any?

        [plan, required]
      end

      def valid_command_evidence(plan, required, evidence)
        return unless command_evidence_checks_pass?(plan, required, evidence)

        build_command_evidence(evidence)
      end

      def command_evidence_checks_pass?(plan, required, evidence)
        return false unless required.include?(evidence.fetch("proof_type").to_s)
        return false unless evidence["status"].to_s == "pass"
        return false unless evidence["exit_status"].is_a?(Integer) && evidence["exit_status"].zero?
        return false unless evidence["command_digest"].to_s == Digest::SHA256.hexdigest(plan.fetch("done_when").to_s)
        return false unless evidence["output_digest"].to_s.match?(/\A[0-9a-f]{64}\z/)
        return false unless evidence["output_bytes"].is_a?(Integer) && evidence["output_bytes"] >= 0
        return false unless evidence["duration_ms"].is_a?(Integer) && evidence["duration_ms"] >= 0

        cwd = evidence["cwd"].to_s
        return false if cwd.empty? || Pathname.new(cwd).absolute? || cwd.split("/").include?("..")

        true
      end

      def build_command_evidence(evidence)
        {
          "proof_type" => evidence.fetch("proof_type").to_s,
          "status" => "pass",
          "exit_status" => 0,
          "command_digest" => evidence.fetch("command_digest"),
          "output_digest" => evidence.fetch("output_digest"),
          "output_bytes" => evidence.fetch("output_bytes").to_i,
          "cwd" => evidence["cwd"].to_s,
          "duration_ms" => evidence.fetch("duration_ms").to_i,
        }
      end

      def verified_repository_write(path, content, repo)
        relative = repository_relative_path(path, repo)
        return unless relative

        digest = Digest::SHA256.hexdigest(content.to_s)
        full = File.join(repo, relative)
        return unless Digest::SHA256.file(full).hexdigest == digest

        [relative, digest]
      end

      def store_repository_write!(repo, relative, digest)
        load_writable_unlocked!
        return false unless @record

        if @record["repository_write_root"] != repo
          @record["repository_write_root"] = repo
          @record["repository_writes"] = {}
        end
        @record["repository_writes"] ||= {}
        @record["repository_writes"][relative] = digest
        @record["last_seen_at"] = now
        persist!
        true
      end
    end
  end
end
