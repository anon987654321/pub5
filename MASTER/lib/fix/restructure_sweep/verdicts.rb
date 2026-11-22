# frozen_string_literal: true

module Master
  module Fix
    # The proposal/verdict pipeline of the tree restructure sweep, split out
    # of restructure_sweep.rb at the verdict responsibility boundary: prompt
    # construction, decommission audit parsing and blocking, the hostile
    # review verdict, commit messages and the run report. The defining file
    # keeps the run loop, candidate collection and orchestration.
    class RestructureSweep
      private

      def attempt(problem, candidate_map: "")
        path, = problem.findings.first
        tree = relative(path).split("/").first
        baseline_scorecard = Restructure::Proof.for(tree, @root).scorecard
        answer = ask(proposal(tree, problem, scorecard: baseline_scorecard, candidate_map:))
        return if answer.strip == "KEEP"

        audit = decommission_audit(answer)
        return report(problem, nil, "mandatory decommission audit missing or incomplete") unless audit

        plan = Restructure::Plan.parse(answer)
        return report(problem, nil, "the answer held no plan") if plan.empty?

        blocker = decommission_blocker(problem, plan, audit)
        return report(problem, plan, blocker, audit:) if blocker

        review = ->(diff) { verdict(problem, plan, diff, scorecard_before: baseline_scorecard, audit:) }
        result = @restructures[tree].call(
          plan,
          message: commit_message(problem, plan),
          review:,
          allowed_operations: problem.candidate_operations,
        )
        report(problem, plan, result, audit:)
      end

      def decommission_blocker(problem, plan, audit)
        operations = Array(plan.operations).map(&:to_s)
        return if (operations & DESTRUCTIVE_OPERATIONS).empty?

        audit_field_blocker(audit) || reference_graph_blocker(problem)
      rescue StandardError => e
        "destructive restructure refused: reference evidence failed closed (#{e.class}: #{e.message.to_s[0, 120]})"
      end

      # The model must prove every reachability class it claims; one INCONCLUSIVE
      # field among the audit answers vetoes a destructive operation outright.
      def audit_field_blocker(audit)
        fields = audit.to_s.split(";").to_h do |entry|
          key, value = entry.strip.split("=", 2)
          [key.to_s.strip, value.to_s.strip]
        end
        uncertain = fields.filter_map do |key, value|
          key if value.match?(/\binconclusive\b/i)
        end
        return "destructive restructure refused: #{uncertain.join(" and ")} reachability is INCONCLUSIVE" if uncertain.any?

        nil
      end

      # Destructive operations additionally need a complete, failure-free
      # reference graph that covers every affected file and leaves no dynamic
      # or unresolved site behind.
      def reference_graph_blocker(problem)
        graph = @reference_graph
        return "destructive restructure refused: repository reference graph unavailable" unless graph

        snapshot = graph.build
        failures = Array(snapshot[:analysis_failures])
        return "destructive restructure refused: reference graph has #{failures.size} analysis failure(s)" unless failures.empty?

        missing = problem.files.reject { |path| graph.includes_path?(path) }
        return "destructive restructure refused: files absent from the reference graph: #{missing.map { |path| relative(path) }.join(", ")}" if missing.any?

        dynamic = problem.files.flat_map { |path| graph.dynamic_for(path) }
        unresolved = problem.files.flat_map { |path| graph.unresolved_for(path) }
        return "destructive restructure refused: #{dynamic.size} dynamic lookup site(s) remain in affected files" if dynamic.any?
        return "destructive restructure refused: #{unresolved.size} unresolved reference(s) remain in affected files" if unresolved.any?

        nil
      end

      def decommission_audit(answer)
        line = answer.to_s.lines.find { |row| row.start_with?("AUDIT:") }
        return unless line

        payload = line.delete_prefix("AUDIT:").strip
        return if payload.length < 80

        entries = payload.split(";").map do |entry|
          key, value = entry.strip.split("=", 2)
          [key.to_s.strip, value.to_s.strip]
        end
        required = AUDIT_FIELDS.map { |field| field.delete_suffix("=") }
        keys = entries.map(&:first)
        return unless keys.uniq.size == keys.size && keys.sort == required.sort
        return if entries.any? { |_key, value| value.empty? }

        payload
      end

      def proposal(tree, problem, scorecard: nil, candidate_map: "")
        scorecard ||= Restructure::Proof.for(tree, @root).scorecard
        format(
          PROPOSE,
          **proposal_sections(tree, problem),
          **proposal_problem_sections(problem, scorecard, candidate_map),
        )
      end

      def findings_section(problem)
        problem.findings.map do |path, rule, message, related|
          related = Array(related).map { |item| relative(item) }.reject { |item| item == relative(path) }
          [
            "#{relative(path)}: #{rule}: #{message}",
            (related.empty? ? nil : "  related: #{related.first(8).join(", ")}"),
          ].compact.join("\n")
        end.join("\n")
      end

      # Plan-level sections are shared by every proposal; they restate the
      # transformation policy, the playbook and the automatic vetoes.
      def proposal_sections(tree, problem)
        {
          transformations: @transformation_plan.prompt,
          preservation: @transformation_plan.preservation_contract.map { |key, value| "  #{key}: #{value}" }.join("\n"),
          contracts: Contracts.for(tree).strip,
          evidence_hierarchy: @transformation_plan.evidence_hierarchy.map { |entry| "  #{entry.fetch("id")}: #{entry.fetch("practice")}" }.join("\n"),
          domain_profile: @transformation_plan.domain_adapters.map { |domain, adapter| "  #{domain}: #{adapter}; smells=#{@transformation_plan.smell_catalog.fetch(domain, []).join(", ")}" }.join("\n"),
          refactoring_methods: playbook_lines("methods") { |entry| "  #{entry.fetch("id")}: #{entry.fetch("action")}" },
          refactoring_playbook: playbook_lines("technique_by_domain") { |domain, techniques| "  #{domain}: #{techniques.join(", ")}" },
          refactoring_checks: playbook_lines("checks") { |check| "  - #{check}" },
          automatic_vetoes: @transformation_plan.automatic_vetoes.map { |veto| "  - #{veto}" }.join("\n"),
        }
      end

      # Problem-level sections bind the prompt to one finding group and to the
      # numbered context the model reads before it answers.
      def proposal_problem_sections(problem, scorecard, candidate_map)
        {
          law: problem.laws.join(", "),
          path: relative(problem.files.first),
          message: "#{problem.reason}; confidence=#{problem.confidence}; problem=#{problem.id}",
          problem_id: problem.id,
          findings: findings_section(problem),
          candidate_operations: problem.candidate_operations.join(", "),
          candidate_map:,
          context: Context.new(
            @root, problem.files.first, related: problem.files.drop(1), scorecard:,
            co_change_window: @transformation_plan.scorecard_policy.fetch("history_window_commits"),
            reference_graph: @reference_graph,
          ).to_s,
        }
      end

      # Methods and checks were validated at boot but never shown to the model;
      # a declared method no prompt carries governs nothing.
      def playbook_lines(section, &)
        @transformation_plan.refactoring_playbook.fetch(section).map(&).join("\n")
      end

      def verdict(problem, plan, diff, scorecard_before: {}, audit: "INCONCLUSIVE: no audit supplied")
        tree = relative(problem.files.first).split("/").first
        answer = ask(
          format(
            ATTACK,
            problem_id: problem.id,
            law: problem.laws.join(", "),
            path: relative(problem.files.first),
            operations: plan.operations.join(", "),
            summary: plan.summary,
            audit: audit.to_s,
            scorecard: scorecard_comparison(tree, plan, scorecard_before),
            diff:,
          ),
        ).strip
        approval = answer.match(/\AAPPROVE:\s+\S.{19,}\z/)
        approval ? nil : "review: #{answer.lines.first.to_s.strip[0, 200]}"
      end

      # The attack turn sees the measured before/after scorecard with numeric
      # deltas; dimensions the proof cannot measure stay inconclusive, not zero.
      def scorecard_comparison(tree, plan, scorecard_before)
        scorecard_after = Restructure::Proof.for(tree, @root).scorecard(extra_paths: plan.paths)
        numeric_delta = scorecard_before.filter_map do |name, value|
          next unless value.is_a?(Numeric) && scorecard_after[name].is_a?(Numeric)

          [name, scorecard_after[name] - value]
        end.to_h
        "before: #{scorecard_before.inspect}\nafter: #{scorecard_after.inspect}\ndelta: #{numeric_delta.inspect}"
      end

      def commit_message(problem, plan)
        title = plan.summary.empty? ? "Restructure #{relative(problem.files.first)}" : plan.summary
        body = [
          "Address laws #{problem.laws.join(", ")} for problem #{problem.id}.",
          "Verify the change with hostile review, parsing, eager load, boot self-test, and related tests.",
        ].join("\n\n")
        [CommitMessage.fit(title), body, CommitMessage::MARKER].join("\n\n")
      end

      def report(problem, plan, result, audit: nil)
        ok = result.is_a?(Result) && result.ok?
        text = if ok then "kept: #{plan.summary}"
               elsif result.is_a?(Result) then result.message
               else result.to_s
               end
        evidence = ok ? result.value!.fetch(:evidence, nil) : nil
        operation = plan&.operations&.last || problem.primary_operation
        Master::Trace::Dmesg.status(
          "restructure0",
          "#{operation} problem=#{problem.id} signals=#{problem.size} #{problem.laws.join(",")} #{relative(problem.files.first)}: #{text[0, 140]}",
        )
        @bus&.publish("fix_loop:restructure", **report_payload(problem, plan, ok, text, evidence, operation, audit))
        result.is_a?(Result) ? result : nil
      end

      # The bus event mirrors the trace line, so downstream consumers can audit
      # the sweep without parsing console output.
      def report_payload(problem, plan, ok, text, evidence, operation, audit)
        {
          path: relative(problem.files.first),
          law: problem.laws.join(","),
          laws: problem.laws,
          problem_id: problem.id,
          operation:,
          candidate_operations: problem.candidate_operations,
          operations: plan&.operations || [],
          confidence: problem.confidence,
          findings: problem.size,
          ok:,
          message: text[0, 300],
          evidence:,
          decommission_audit: audit&.slice(0, 1_200),
        }
      end
    end
  end
end
