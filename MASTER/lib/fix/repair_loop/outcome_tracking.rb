# frozen_string_literal: true

require_relative "../autofix_guard"
require_relative "../antigen_store"
require_relative "../../trace/causal_trace"
require "digest"

module Master
  module Fix
    class RepairLoop
      # Aggregates one batch's per-violation fix_violation results into a
      # pass-level outcome and records it to @learnings -- separate concern
      # from actually attempting a fix (fix_strategies.rb) or verifying one
      # (fix_verification.rb).
      module OutcomeTracking
        private

        # Only a genuine, attempted-and-failed fix should count as :stuck for
        # fix_quality's purposes -- a violation skipped by policy (confidence
        # check, stale fingerprint) was never actually attempted, and counting
        # it the same as a real defect silently poisons that rule's quality
        # score, which then deprioritizes it further next round: exactly the
        # "banned a working tool over recoverable failures" trap OpenCrabs
        # documented (feedback_policy.rs, issue #236) after making the same
        # mistake. :skipped is still recorded (queryable) but excluded from
        # fix_quality's denominator entirely.
        OUTCOMES = %i[
          applied commit_refused no_proposal model_failed reflexion_rejected consensus_rejected
          rejected out_of_scope file_timeout skip_rejected_twice skip_confidence skip_fingerprint
          skip_fused skip_law_budget skip_protected needs_person
        ].freeze

        def fix_batch(violations)
          grouped = violations.group_by { |violation| violation[:file].to_s }
          grouped.each do |file, findings|
            findings.each do |violation|
              RunLedger.record_discovery(
                file:, law: violation[:law] || @law.id, line: violation[:line],
                message: violation[:message], severity: violation[:severity],
              )
            end
            findings.drop(1).each do |violation|
              RunLedger.record_disposition(
                file:, law: violation[:law] || @law.id, outcome: :not_attempted_same_file,
                reason: "one finding per file is selected in this batch; this finding remains discovered",
              )
            end
          end

          unique = violations.uniq { |violation| violation[:file] }
          results = []
          unique.each_with_index do |violation, index|
            # The stall guard's stop ends the repair now: checked only at pass boundaries, a stopped
            # run kept attempting files for 40 minutes after it said STOPPING.
            if RunBudget.stopping
              unique[index..].each do |pending|
                RunLedger.record_disposition(
                  file: pending[:file], law: pending[:law] || @law.id, outcome: :not_attempted_budget,
                  reason: "run budget or stall stop was active before this finding was attempted",
                )
              end
              break
            end

            result = attempt(violation)
            results << result
            if result.to_s.start_with?("skip_")
              RunLedger.record_disposition(
                file: violation[:file], law: violation[:law] || @law.id, outcome: result,
                reason: "repair policy gate skipped model work for this finding",
              )
            end
            if immediate_delivery_boundary?(result)
              unique.drop(index + 1).each do |pending|
                RunLedger.record_disposition(
                  file: pending[:file], law: pending[:law] || @law.id, outcome: :not_attempted_delivery_boundary,
                  reason: "the one-file delivery boundary ended this batch after #{result}",
                )
              end
              break
            end
          end
          @all_skipped = results.any? && results.all? { |r| r.to_s.start_with?("skip_") }
          log_outcome_breakdown(results)
          # A commit_refused fix still counts as work the stage must account for:
          # a refused repair is put back, but one whose push failed is committed
          # locally, and llm_fixed > 0 is what sends the stage-end delivery after it.
          results.count { |r| r == :applied || r == :commit_refused }
        end

        # Three refusals stand between a violation and the model, all skips so
        # none poisons the rule's quality score: a protected file, a tuple that
        # already failed ToolBreaker::LIMIT times against an unchanged file, and a
        # law past its RunBudget share. What the attempt then costs is billed to its law.
        #
        # The protected check is the one AutofixGuard gives the deterministic
        # writers. Without it a model repair wrote its candidate into a protected
        # file to test it, and RunBudget's protected-path watch stopped the run.
        def attempt(violation)
          return :skip_protected if protected_target?(violation)

          law = @law.id
          state = ToolBreaker.state_of(violation)
          return :skip_fused if ToolBreaker.refuse?(law, violation, state)
          return :skip_law_budget if RunBudget.law_limit_exceeded?(law)

          usd, tokens = RunBudget.run_spend
          result = fix_violation(violation)
          ToolBreaker.record(law, violation, state, result)
          record_failure_antigen(violation, state, result)
          after_usd, after_tokens = RunBudget.run_spend
          RunBudget.note_law_cost(law, after_usd - usd, after_tokens - tokens)
          result
        end

        FAILURE_ANTIGEN_OUTCOMES = %i[no_proposal reflexion_rejected consensus_rejected rejected].freeze

        # A failed, model-produced repair becomes durable memory only for the
        # exact source bytes that produced it. Changing the file reopens the gate.
        def record_failure_antigen(violation, source_sha256, outcome)
          return unless FAILURE_ANTIGEN_OUTCOMES.include?(outcome)
          return unless source_sha256.to_s.match?(/\\A[0-9a-f]{64}\\z/)

          repo_root = defined?(Master::REPO_ROOT) ? File.expand_path(Master::REPO_ROOT) : File.expand_path(@root)
          absolute = File.expand_path(violation[:file].to_s, repo_root)
          return unless absolute.start_with?(repo_root + File::SEPARATOR)

          boundary = absolute.delete_prefix(repo_root + File::SEPARATOR)
          law = violation[:law].to_s.empty? ? @law.id : violation[:law].to_s
          defect_digest = Digest::SHA256.hexdigest(violation[:message].to_s)[0, 16]
          defect_class = "#{outcome}:#{defect_digest}"
          store = AntigenStore.new(root: repo_root)
          return if store.known?(law:, boundary:, defect_class:, source_sha256:)

          trace_context = Master::Trace::CausalTrace.current
          store.record(
            law:, boundary:, defect_class:,
            evidence: {
              source_sha256:, outcome: outcome.to_s, attempts: 1,
              run_id: trace_context && trace_context[:run_id],
            },
            note: "repair attempt rejected against unchanged source",
            severity: "warning",
          )
        rescue StandardError => error
          Master::Ground::Swallow.log(error, context: "repair_loop.record_failure_antigen", event_bus: @bus, law: @law.id)
        end

        def protected_target?(violation)
          AutofixGuard.protected_reason(File.expand_path(violation[:file].to_s, @root), root: @root)
        end

        def immediate_delivery_boundary?(result)
          return false unless @committer
          return false if stage_commit_mode?

          %i[applied commit_refused].include?(result)
        end

        # A single aggregate line per rule/pass, not one per violation --
        # thousands of violations would otherwise flood the dmesg stream the
        # way per-file rubocop output already did earlier this session. Every
        # outcome appears, not just the skips: a pass that proposes nothing and
        # a pass whose proposals all die in review are different problems, and
        # "0 fixed" says neither.
        def log_outcome_breakdown(results)
          @batch_breakdown = {}
          return if results.empty?

          tally = results.tally
          @batch_breakdown = tally
          parts = tally.filter_map { |outcome, count| "#{count} #{outcome}" if count.positive? }
          Master::Trace::Dmesg.status("fix0", "#{@law.id}, #{results.size} tried: #{parts.join(", ")}")
        end

        def pass_outcome(fixed)
          return :human_decision if @person_required
          return :fixed if fixed.positive?
          return :skipped if @all_skipped

          :stuck
        end

        def record_outcomes(files, outcome)
          return unless @learnings

          extensions = files.filter_map do |file|
            ext = File.extname(file).downcase.delete(".")
            ext unless ext.empty?
          end
          ext = extensions.tally.max_by { |_, count| count }&.first || "unknown"
          @learnings.record(law: @law.id, file_type: ext, outcome:)
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "repair_loop.record_outcomes", event_bus: @bus, law: @law.id)
        end
      end
    end
  end
end
