# frozen_string_literal: true

module Master
  module Fix
    class Wishlist
      # How ledger rows move: queued -> claimed -> applied -> verified, with
      # stale, blocked and abandoned-claim exits, plus reflection intake from a
      # finished run. Every mutation here happens under the caller's ledger
      # lock; each method returns the rows it touched.
      def claimable(target:, limit: BATCH_SIZE, run_id: nil)
        with_ledger_lock do
          ledger = load_ledger
          head = @git.head
          changed = false
          rows = ledger["proposals"].filter_map do |proposal|
            row, updated = claimable_row(proposal, head, target:, run_id:)
            changed = true if updated
            row
          end.then { |rows| Personas.order(rows) }.first(limit.to_i)

          save_ledger(ledger) if changed
          rows
        end
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Fix::Wishlist.claimable", event_bus: @bus)
        []
      end

      def claim!(proposals, run_id:)
        with_ledger_lock do
          ids = Array(proposals).map { |proposal| proposal["uid"].to_s }.reject(&:empty?)
          return [] if ids.empty?

          ledger = load_ledger
          now = Master::Clock.utc_now.iso8601
          claimed = ledger["proposals"].filter_map do |proposal|
            next unless ids.include?(proposal["uid"].to_s) && proposal["status"] == "queued"

            proposal["status"] = "claimed"
            proposal["claimed_at"] = now
            proposal["claimed_run"] = run_id.to_s
            proposal
          end
          save_ledger(ledger)
          @bus&.publish("wishlist:claimed", run_id:, count: claimed.size)
          claimed
        end
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Fix::Wishlist.claim!", event_bus: @bus)
        []
      end
      # FixLoop::PassExecution asks for `claim`; without it every wishlist round raised NoMethodError.
      alias claim claim!

      def mark_attempt(proposal_id:, fixed:, status:, message:, run_id:)
        with_ledger_lock do
          ledger = load_ledger
          proposal = ledger["proposals"].find { |item| item["uid"].to_s == proposal_id.to_s }
          return unless proposal

          attempts = record_attempt(proposal, fixed:, status:, message:, run_id:)
          save_ledger(ledger)
          publish_attempt(proposal_id, proposal, status, fixed, attempts)
          proposal
        end
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Fix::Wishlist.mark_attempt", event_bus: @bus)
        nil
      end

      def mark_delivered(proposal_ids:, run_id:)
        with_ledger_lock do
          ids = Array(proposal_ids).map(&:to_s)
          return [] if ids.empty?

          ledger = load_ledger
          changed = ledger["proposals"].filter_map { |proposal| deliver_row(proposal, ids, run_id) }
          save_ledger(ledger) unless changed.empty?
          changed
        end
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Fix::Wishlist.mark_delivered", event_bus: @bus)
        []
      end

      def mark_verified(proposal_ids:, run_id:)
        with_ledger_lock do
          ids = Array(proposal_ids).map(&:to_s)
          return [] if ids.empty?

          ledger = load_ledger
          changed = ledger["proposals"].filter_map { |proposal| verify_row(proposal, ids, run_id) }
          save_ledger(ledger) unless changed.empty?
          changed
        end
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Fix::Wishlist.mark_verified", event_bus: @bus)
        []
      end

      def record_reflection!(reflection:, state:, target:, run_id:)
        with_ledger_lock do
          return false unless reflection.respond_to?(:repair?) && reflection.repair?
          law, anchor, evidence, change = reflection_fields(reflection)
          return false unless law

          item = reflection_item(reflection, law, anchor, evidence, change)
          ledger = load_ledger
          added = merge_new_items!(ledger, [item], state:, target:, run_id:)
          save_ledger(ledger) if added.positive?
          @bus&.publish("wishlist:reflection", added:, law:, anchor:, run_id:)
          added.positive?
        end
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Fix::Wishlist.record_reflection!", event_bus: @bus)
        false
      end

      private

      # One pass over a row for claimability: reclaimed claims, auto
      # implementations only, live anchors, current digests, rebased heads, no
      # run-local repeats. Returns [row or nil, mutated?].
      def claimable_row(proposal, head, target:, run_id:)
        changed = reclaim_claim!(proposal)
        return [nil, changed] unless proposal["status"] == "queued"
        return [nil, changed] unless AUTO_IMPLEMENTATIONS.include?(proposal["implementation"])

        anchor = anchor_file(proposal["anchor"])
        unless anchor
          stale_missing_anchor!(proposal)
          return [nil, true]
        end
        return [nil, changed] unless anchor_in_target?(anchor, target)
        return [nil, true] if stale_anchor!(proposal, anchor)

        keep, rebased = rebase_row(proposal, head, run_id)
        return [nil, changed || rebased] unless keep

        [proposal, changed]
      end

      # A claim left over from a crashed run re-enters the queue.
      def reclaim_claim!(proposal)
        return false unless proposal["status"] == "claimed"

        proposal["status"] = "queued"
        proposal.delete("claimed_at")
        proposal.delete("claimed_run")
        true
      end

      def stale_missing_anchor!(proposal)
        proposal["status"] = "stale"
        proposal["stale_reason"] = "anchor missing"
      end

      # Stales a row whose recorded anchor digest no longer matches the file on
      # disk and tells the bus; true when the row was staled.
      def stale_anchor!(proposal, anchor)
        recorded_digest = proposal["anchor_sha256"].to_s
        current_digest = Digest::SHA256.file(anchor).hexdigest
        return false unless recorded_digest.empty? || recorded_digest != current_digest

        proposal["status"] = "stale"
        proposal["stale_reason"] = "anchor changed since proposal"
        proposal["stale_at"] = Master::Clock.utc_now.iso8601
        @bus&.publish("wishlist:stale", id: proposal["uid"], reason: proposal["stale_reason"])
        true
      end

      # Rebases an anchor-verified row onto the current head and drops
      # run-local repeats. Returns [keep?, mutated?].
      def rebase_row(proposal, head, run_id)
        return [false, false] if head.to_s.empty?

        changed = false
        if proposal["basis_head"].to_s != head.to_s
          proposal["basis_head"] = head
          proposal["rebased_at"] = Master::Clock.utc_now.iso8601
          changed = true
        end
        keep = !(run_id && proposal["last_attempt_run"].to_s == run_id.to_s)
        [keep, changed]
      end

      # Applies one attempt outcome under the bounded-retry policy: fixes keep
      # the claim, human decisions and exhausted attempts block, the rest requeue.
      def record_attempt(proposal, fixed:, status:, message:, run_id:)
        attempts = proposal.fetch("attempts", 0).to_i + 1
        proposal["attempts"] = attempts
        proposal["last_attempt_run"] = run_id.to_s
        proposal["last_outcome"] = status.to_s
        proposal["last_message"] = message.to_s.byteslice(0, 500)

        if fixed.to_i.positive?
          proposal["status"] = "claimed"
          proposal["last_fixed"] = fixed.to_i
        elsif %i[human_decision needs_person].include?(status.to_sym)
          proposal["status"] = "blocked"
        elsif attempts >= MAX_ATTEMPTS
          proposal["status"] = "blocked"
          proposal["blocked_reason"] = "attempt limit reached"
        else
          proposal["status"] = "queued"
        end
        attempts
      end

      def publish_attempt(proposal_id, proposal, status, fixed, attempts)
        @bus&.publish(
          "wishlist:attempt",
          id: proposal_id,
          status: proposal["status"],
          outcome: status,
          fixed: fixed.to_i,
          attempts:,
        )
      end

      # Stamps a claimed, fixed row as applied and clears the claim markers.
      def deliver_row(proposal, ids, run_id)
        return unless ids.include?(proposal["uid"].to_s)
        return unless proposal["status"] == "claimed"
        return unless proposal.fetch("last_fixed", 0).to_i.positive?

        proposal["status"] = "applied"
        proposal["applied_at"] = Master::Clock.utc_now.iso8601
        proposal["applied_run"] = run_id.to_s
        proposal.delete("claimed_at")
        proposal.delete("claimed_run")
        proposal
      end

      # Runs the proof contract on an applied row and files the outcome.
      def verify_row(proposal, ids, run_id)
        return unless ids.include?(proposal["uid"].to_s)
        return unless proposal["status"] == "applied"

        proof = ProofContract.verify(proposal, root: @root)
        proposal["proof_state"] = proof[:state].to_s
        proposal["proof_checks"] = Array(proof[:checks]).first(6)
        apply_proof_state(proposal, proof, run_id)
        proposal
      end

      # Proven rows verify, failed proofs block, and open proofs stay applied
      # pending external validation.
      def apply_proof_state(proposal, proof, run_id)
        case proof[:state]
        when :proven
          proposal["status"] = "verified"
          proposal["verified_at"] = Master::Clock.utc_now.iso8601
          proposal["verified_run"] = run_id.to_s
        when :failed
          proposal["status"] = "blocked"
          proposal["blocked_reason"] = "wishlist proof failed"
          proposal["blocked_at"] = Master::Clock.utc_now.iso8601
        else
          proposal["status"] = "applied"
          proposal["verification_reason"] = "proof contract requires external validation"
        end
      end

      # A reflection is only usable when law, anchor, evidence and change all
      # carry text; returns those four strings, or nil when any is empty.
      def reflection_fields(reflection)
        fields = [reflection.law, reflection.anchor, reflection.evidence, reflection.next_action].map(&:to_s)
        fields.any?(&:empty?) ? nil : fields
      end

      def reflection_item(reflection, law, anchor, evidence, change)
        {
          "id" => "reflection_#{Digest::SHA256.hexdigest([law, anchor, evidence, change].join("\n"))[0, 16]}",
          "title" => reflection.summary.to_s,
          "rationale" => reflection.summary.to_s,
          "anchor" => anchor,
          "change" => change,
          "effort" => "medium",
          "reversibility" => "guarded",
          "implementation" => "next_fix",
          "evidence" => evidence,
          "proof" => ["same law and anchor must hold after mutation"],
        }
      end

    end
  end
end
