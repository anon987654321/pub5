# frozen_string_literal: true

module Master
  module Fix
    class Wishlist
      # The model-facing and read-only side: the brief the agent answers, the
      # YAML response parsing and normalization, and the pending-queue
      # renderings other subsystems consume. No ledger mutation lives here.
      def render_pending(target:, limit: BATCH_SIZE)
        rows = claimable(target:, limit:)
        return if rows.empty?

        <<~TEXT.strip
          Pending automatic convergence proposals from the durable /fix ledger.
          Treat each queued next_fix proposal as an actual bounded repair target.
          Do not treat this as a TODO list. Re-check the live source and constitutional
          rules before mutation. Unsupported, stale, operator-owned, or research-only
          work is not automatically completed.

          #{pending_bodies(rows).join("\n\n")}
        TEXT
      end

      def pending_titles(target:, limit: BATCH_SIZE)
        claimable(target:, limit:).map { |proposal| proposal["title"].to_s }.reject(&:empty?)
      end

      def pending_count(target:)
        claimable(target:, limit: MAX_PROPOSALS).size
      end

      def self.pending_context(root, target: root, limit: BATCH_SIZE)
        new(root:, agent: nil).render_pending(target:, limit:)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Fix::Wishlist.pending_context")
        nil
      end

      def self.pending_titles(root, target: root, limit: BATCH_SIZE)
        new(root:, agent: nil).pending_titles(target:, limit:)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Fix::Wishlist.pending_titles")
        []
      end

      def self.findings(proposals, root:)
        Array(proposals).filter_map do |proposal|
          path, line = proposal["anchor"].to_s.split(":", 2)
          next if path.to_s.empty? || line.to_s !~ /\A\d+\z/

          file = File.expand_path(path, root)
          next unless File.file?(file)

          build_finding(proposal, file, line.to_i)
        end
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Fix::Wishlist.findings")
        []
      end

      # Builds the law finding for one proposal with a live anchor file.
      def self.build_finding(proposal, file, line)
        fingerprint = Master::Review::Scan::SemanticFingerprint.for(File.read(file, encoding: "UTF-8"))
        proof = Array(proposal["proof"]).join(", ")
        {
          law: LAW_ID,
          file:,
          line:,
          severity: :warning,
          confidence: 1.0,
          reversibility: proposal["reversibility"].to_s,
          blast_radius: { files_touched: 1 },
          fingerprint:,
          message: "#{proposal["title"]}: #{proposal["rationale"]}",
          fix: [
            proposal["change"],
            "Evidence: #{proposal["evidence"]}",
            ("Proof contract: #{proof}" unless proof.empty?),
          ].compact.join("\n"),
          wishlist_id: proposal["uid"].to_s,
          wishlist_proposal: proposal,
        }
      end
      private_class_method :build_finding

      private

      # Renders each queued proposal as its labeled field block.
      def pending_bodies(rows)
        rows.map do |proposal|
          proof = Array(proposal["proof"]).join(", ")
          [
            "proposal: #{proposal["uid"]}",
            "title: #{proposal["title"]}",
            "anchor: #{proposal["anchor"]}",
            "change: #{proposal["change"]}",
            "evidence: #{proposal["evidence"]}",
            "proof: #{proof}",
            "effort: #{proposal["effort"]}",
            "reversibility: #{proposal["reversibility"]}",
          ].join("\n")
        end
      end

      # The full brief: intro, run context, item schema, guidance and output
      # contract, joined with single blank lines.
      def prompt(orientation:, state:, target:, run_id:)
        [
          prompt_intro,
          prompt_run(state:, target:, run_id:, orientation:),
          prompt_schema,
          prompt_guidance,
          prompt_footer,
        ].join("\n\n") + "\n"
      end

      def prompt_intro
        <<~TEXT.chomp
          You are proposing the next bounded work queue after a completed MASTER /fix run.
          Do not claim a defect unless the supplied evidence supports it.
          Do not repeat work that is already marked done. Prefer concrete improvements
          that a later /fix can implement and verify.
        TEXT
      end

      def prompt_run(state:, target:, run_id:, orientation:)
        <<~TEXT.chomp
          Run:
          state: #{state}
          target: #{target}
          run_id: #{run_id}

          Orientation:
          #{orientation}
        TEXT
      end

      def prompt_schema
        <<~TEXT.chomp
          Produce 0 to #{MAX_NEW_ITEMS} wishlist items as YAML.
          Each item must contain:
          - id: snake_case
          - title: short human-readable name
          - rationale: one sentence
          - anchor: repository-relative path:line, or run:<state>
          - change: one concrete implementation sentence
          - effort: cheap, medium, or deep
          - reversibility: reversible, guarded, or operator
          - implementation: next_fix, research, or operator
          - evidence: one sentence using only facts present in the supplied orientation/run
          - proof: 0 to 6 concrete checks that can verify the proposed change
        TEXT
      end

      def prompt_guidance
        <<~TEXT.chomp
          Prefer automatic next_fix only for bounded, evidence-backed changes anchored in
          a real file. Use research when more investigation is needed and operator when
          a human, credential, device, external service, irreversible decision, or
          real-world observation is required.
        TEXT
      end

      def prompt_footer
        <<~TEXT.chomp
          Do not invent external purchases, users, scale numbers, credentials, incidents,
          benchmarks, or measurements. Never pad the list to reach a quota.
          Return only the YAML array. No Markdown fences and no prose.
        TEXT
      end

      def parse(text)
        body = text.to_s.sub(/\A.*?(?=^- |\A- )/m, "").sub(/\n```.*\z/m, "").strip
        data = YAML.safe_load(body, aliases: false)
        raise ParseError, "wishlist response must be a YAML array" unless data.is_a?(Array)

        data
      rescue Psych::Exception => e
        raise ParseError, "wishlist response contains invalid YAML: #{e.message}"
      end

      def normalize(items)
        rows = items.filter_map { |item| normalize_item(item) }
        rows.uniq { |item| [item["id"], item["anchor"], item["change"]] }.first(MAX_NEW_ITEMS)
      end

      # Coerces one raw model answer into the canonical proposal shape, or nil
      # when it is junk, incomplete, or anchored nowhere real.
      def normalize_item(item)
        return unless item.is_a?(Hash)

        id = slug(item["id"] || item["title"])
        anchor = item["anchor"].to_s.strip
        return unless complete_answer?(item, id)
        return unless valid_anchor?(anchor)

        reversibility = normalize_choice(item["reversibility"], %w[reversible guarded operator], "guarded")
        implementation = normalized_implementation(item, anchor, reversibility)
        normalized_item(item, id, anchor, reversibility, implementation)
      end

      # Rejects answers missing an id, title, rationale, change or evidence.
      def complete_answer?(item, id)
        return false if id.empty?
        return false if item["title"].to_s.strip.empty? || item["rationale"].to_s.strip.empty?
        return false if item["change"].to_s.strip.empty? || item["evidence"].to_s.strip.empty?

        true
      end

      # Operator reversibility forces operator implementation, and a next_fix
      # without a real anchor file degrades to operator too.
      def normalized_implementation(item, anchor, reversibility)
        implementation = normalize_choice(item["implementation"], %w[next_fix research operator], "operator")
        implementation = "operator" if reversibility == "operator" && implementation == "next_fix"
        implementation = "operator" unless anchor_file(anchor) || implementation != "next_fix"
        implementation
      end

      def normalized_item(item, id, anchor, reversibility, implementation)
        {
          "id" => id,
          "title" => item["title"].to_s.strip,
          "rationale" => item["rationale"].to_s.strip,
          "anchor" => anchor,
          "change" => item["change"].to_s.strip,
          "effort" => normalize_choice(item["effort"], %w[cheap medium deep], "medium"),
          "reversibility" => reversibility,
          "implementation" => implementation,
          "evidence" => item["evidence"].to_s.strip,
          "proof" => Array(item["proof"]).map { |value| value.to_s.strip }.reject(&:empty?).first(6),
        }
      end

      def valid_anchor?(anchor)
        return true if anchor.match?(/\Arun:[a-z_]+\z/i)

        !anchor_file(anchor).nil?
      end

      def normalize_choice(value, allowed, fallback)
        choice = value.to_s.downcase
        allowed.include?(choice) ? choice : fallback
      end

      def slug(value)
        value.to_s.downcase.gsub(/[^a-z0-9]+/, "_").gsub(/\A_+|_+\z/, "")[0, 64]
      end

    end
  end
end
