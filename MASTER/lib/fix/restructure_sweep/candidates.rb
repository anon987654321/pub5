# frozen_string_literal: true

module Master
  module Fix
    # Candidate discovery and ranking for the tree restructure sweep, split
    # out of restructure_sweep.rb at the candidate-collection responsibility
    # boundary: structural findings become rotated, scored problem rows, the
    # rows render into the read-only candidate map shown to the model, and
    # sweep-target resolution plus veto classification live here too. The
    # defining file keeps the run loop, prompts and verdict pipeline.
    class RestructureSweep
      def ranked_candidate_map(problems)
        score_min, score_max = @transformation_plan.candidate_map_policy.fetch("score_range").map(&:to_i)
        Array(problems).map do |problem|
          signal_count = problem.findings.size + [problem.laws.size - 1, 0].max + [problem.files.size - 1, 0].max
          payoff = [[signal_count, score_min].max, score_max].min
          risk = (problem.candidate_operations.map { |operation| OPERATION_RISK.fetch(operation, score_max) }.max || score_max)
            .clamp(score_min, score_max)
          { problem:, payoff:, risk:, ratio: payoff.to_f / risk }
        end.sort_by do |row|
          [-row.fetch(:ratio), -row.fetch(:payoff), row.fetch(:risk), row.fetch(:problem).id]
        end
      end

      # The map is evidence-backed, scored, and read-only. If the tree has fewer
      # than the requested number of candidates, report the shortfall instead of
      # inventing filler or repeating the same move under different names.
      def render_candidate_map(rows)
        policy = @transformation_plan.candidate_map_policy
        wanted = Integer(policy.fetch("minimum_alternatives"))
        min_paths = Integer(policy.fetch("minimum_distinct_target_paths"))
        distinct_paths = rows.flat_map { |row| row.fetch(:problem).files }.uniq
        score_max = policy.fetch("score_range").last.to_i
        shortfall = [wanted - rows.size, 0].max
        path_shortfall = [min_paths - distinct_paths.size, 0].max
        shown = shown_rows(rows, score_max)
        [
          "Evidence-backed candidates: #{rows.size}; distinct target paths: #{distinct_paths.size}.",
          "Requested minimums: #{wanted} candidates and #{min_paths} distinct target paths; shortfalls: #{shortfall} candidates and #{path_shortfall} paths.",
          "Shortfalls are reported, never padded. Payoff/risk is a deterministic ranking aid, not an equivalence proof.",
          *shown,
          (rows.size > shown.size ? "  omitted #{rows.size - shown.size} lower-ranked candidates" : nil),
        ].compact.join("\n")
      end

      # [path, law, message, related_paths] for each repository-surface finding, smallest moves first;
      # within a rule the order rotates by run, so every finding comes up. Dead
      # subtrees and cross-file architecture defects carry their evidence paths
      # into the proposal rather than collapsing to one filename.
      def candidates(target, run_id)
        found = Context.structural_findings(target)
        problems = ProblemGraph.new(plan: @transformation_plan).call(found)
        return [] if problems.empty?

        seed = Digest::SHA256.hexdigest(run_id.to_s)[0, 8].to_i(16)
        rotated = problems.rotate(seed % problems.size)
        announce_problems(target, found, rotated)
        rotated
      end

      def policy_veto?(result)
        result.is_a?(Result) && !result.ok? &&
          result.message.to_s.match?(/MIXED_COMMIT|BATCH_DELETE|UNALIASED_MOVE|restructure refused|immutable|off limits|outside .*policy|stale read required/i)
      end

      def sweep_targets(target)
        expanded = File.expand_path(target.to_s, @root)
        return TREES.filter_map do |tree|
          path = File.join(@root, tree)
          path if File.directory?(path)
        end if expanded == File.expand_path(@root)

        return [] unless TREES.include?(File.basename(expanded))
        return [] unless File.dirname(expanded) == File.expand_path(@root)

        [expanded]
      end

      private

      # At most 30 candidates are shown in the map; the caller summarizes the
      # rest as omitted, so the prompt states the shortfall it reports.
      def shown_rows(rows, score_max)
        rows.first(30).map do |row|
          problem = row.fetch(:problem)
          findings = problem.findings.map { |path, law, message, _related| "#{relative(path)} #{law} #{message}" }
          format(
            "  %s payoff=%d/%d risk=%d/%d ratio=%.2f operation=%s paths=%s evidence=%s",
            problem.id, row.fetch(:payoff), score_max, row.fetch(:risk), score_max, row.fetch(:ratio),
            problem.candidate_operations.join(","), problem.files.map { |path| relative(path) }.join(","),
            findings.join(" | ")
          )
        end
      end

      # The problem census feeds both the trace and the bus event, so a run log
      # and its replay agree on what the sweep saw.
      def announce_problems(target, found, rotated)
        multifinding = rotated.count { |problem| problem.size > 1 }
        multisignal = rotated.count(&:multi_signal?)
        candidate_count = rotated.sum { |problem| problem.candidate_operations.size }
        Master::Trace::Dmesg.status(
          "restructure0",
          "#{found.size} finding(s) -> #{rotated.size} problem(s), " \
          "#{multifinding} multi-finding, #{multisignal} multi-signal, " \
          "#{candidate_count} candidate transformation(s)",
        )
        @bus&.publish("fix_loop:restructure_problems", **problem_counts(target, found, rotated, multifinding, multisignal, candidate_count))
      end

      def problem_counts(target, found, rotated, multifinding, multisignal, candidate_count)
        {
          target: relative(target),
          findings: found.size,
          problems: rotated.size,
          multi_finding: multifinding,
          multi_signal: multisignal,
          candidates: candidate_count,
        }
      end
    end
  end
end
