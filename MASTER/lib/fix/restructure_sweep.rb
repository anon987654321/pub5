# frozen_string_literal: true

require "digest"
require_relative "restructure"
require_relative "restructure_sweep/context"
require_relative "restructure_sweep/contracts"
# The re-opened parts of this class, one responsibility each; every path is
# listed in data/autoload.yml under autoload.reopens_a_constant_defined_elsewhere.
require_relative "restructure_sweep/candidates"
require_relative "restructure_sweep/verdicts"
require_relative "transformation_plan"
require_relative "problem_graph"
require_relative "commit_message"

module Master
  module Fix
    # /fix treats structural consolidation as a normal repair stage. At the start
    # of a tree-level run it takes one bounded first pass; after content repair it
    # keeps sweeping until structural convergence. The model proposes the files
    # to write and delete, a second hostile turn attacks the applied diff, and
    # Restructure keeps the change only if the proof holds.
    #
    # MASTER_FIX_RESTRUCTURES=0 switches it off; MASTER_FIX_RESTRUCTURE_ATTEMPTS
    # caps the findings tried per run, each costing two model calls.
    class RestructureSweep
      ATTEMPTS = Integer(ENV.fetch("MASTER_FIX_RESTRUCTURE_ATTEMPTS", 4))
      ROUNDS = Integer(ENV.fetch("MASTER_FIX_RESTRUCTURE_ROUNDS", 4))
      KEEPS = 3
      AUDIT_FIELDS = %w[purpose= owner= inbound= runtime= dynamic= config= external= tests= data= revival=].freeze
      FIRST_ATTEMPTS = 1
      FIRST_ROUNDS = 1
      FIRST_KEEPS = 1
      TREES = Contracts::BY_TREE.keys.freeze
      OPERATION_RISK = {
        "remove" => 5, "rename" => 4, "relocate" => 4, "merge" => 4,
        "split" => 3, "defragment" => 3, "decouple" => 3, "hoist" => 2,
        "flatten" => 2, "reorder" => 2, "simplify" => 2, "reflow" => 1,
        "recommend" => 1
      }.freeze
      DESTRUCTIVE_OPERATIONS = %w[remove rename relocate merge split flatten hoist defragment decouple].freeze

      PROPOSE = <<~TEXT
        Restructure one underlying problem in this tree rather than fixing its findings independently.

        Autonomous surgery rules:
        - Read the archaeology below before deciding that a file is dead or should move.
        - Run a decommission and simplification audit over the affected subsystem before choosing an operation.
        - Inventory runtime registrations, dependency manifests and lockfiles, package declarations, boot hooks, config readers, require/load/import sites, autoloads, reflection, command entrypoints, external scripts, deployment paths, tests and documented public contracts.
        - Search reverse references across the repository, not only the supplied excerpts. A missing direct text match is not proof when dispatch, constants, globbing, registries or generated paths can reach the component.
        - Classify each candidate KEEP, CONSOLIDATE, DECOMMISSION or HUMAN_DECISION; cite exact evidence paths and every known live consumer.
        - DECOMMISSION only when source, runtime, dynamic and external reachability are disproved, the purpose is obsolete, required data is preserved, and regression coverage proves the surviving path.
        - Parked is not the same as dead. Preserve parked capabilities with a real revival condition; remove stale activation hooks and duplicated policy only when every reader is accounted for.
        - Prefer deleting a whole duplicate mechanism over preserving a compatibility layer for a dead consumer. Do not remove a capability merely because it is currently disabled.
        - Tests are evidence, not production callers. If a deleted test is the only consumer, say so in SUMMARY.
        - Recalculate the recursive tree census after every kept restructure; hidden nested growth is not free.
        - Reconcile the structural ratchet when the measured core gets smaller. Keep the recorded ceiling honest.

        Problem: %<problem_id>s
        Laws: %<law>s
        Why these findings were grouped: %<message>s

        Findings:
        %<findings>s

        Read-only candidate map. No source has changed during this phase:
        %<candidate_map>s

        Candidate transformations for the selected problem:
        %<candidate_operations>s

        Choose exactly one transformation for this commit. Map candidates before writing; score payoff and risk from
        evidence, compare distinct target paths, and never pad the candidate set with paraphrases. Apply one operation,
        verify it, and only then use its result as the next step's baseline.
        The transformation policy below supplies triggers, vetoes, the DRY/KISS decision table, scorecard, and proof.
        Similarity alone never justifies consolidation. Behaviour, meaning, import paths, and public contracts must not change.

        %<transformations>s

        The preservation contract is mandatory:
        %<preservation>s

        Evidence hierarchy (strongest first):
        %<evidence_hierarchy>s

        Domain adapters and smell vocabulary:
        %<domain_profile>s

        Refactoring methods (how to work):
        %<refactoring_methods>s

        Refactoring technique playbook:
        %<refactoring_playbook>s

        Refactoring checks (what a kept change must satisfy):
        %<refactoring_checks>s

        Automatic vetoes:
        %<automatic_vetoes>s

        Decommission evidence and simplification report (mandatory):
        Before selecting any operation, state the candidate's purpose and owner; list exact inbound references, runtime activation paths, dynamic dispatch/reflection/glob paths, config and dependency-manifest readers, external/deploy consumers, tests, retained data and revival conditions. Separate proven absence from an unsearched or dynamic path. If evidence is incomplete, KEEP or HUMAN_DECISION; do not infer deletion from age, naming, a parked label or a zero-result grep.

        The response must include one machine-readable, single-line AUDIT record with every field below. Use an exact repository path for each claimed reference or the word none; use INCONCLUSIVE when a path was not proved. Do not use semicolons inside values; semicolons separate fields. A missing, empty or partial field is a refusal, not a harmless omission:
        purpose=...; owner=...; inbound=...; runtime=...; dynamic=...; config=...; external=...; tests=...; data=...; revival=...

        The tree, and the contracts to keep:
        %<contracts>s

        If no restructure is both sound and clearly better, answer exactly: KEEP
        The context below numbers each line for reference; never copy the numbers.
        Otherwise answer in exactly this format, whole file contents, no code fences:
        SUMMARY: <one line: what moved where, and why>
        OPERATIONS: <one candidate transformation name, in constitutional order>
        AUDIT: purpose=...; owner=...; inbound=...; runtime=...; dynamic=...; config=...; external=...; tests=...; data=...; revival=...
        === WRITE <path from the repository root, e.g. MASTER/lib/fix/x.rb>
        <complete file content>
        === DELETE <path from the repository root>
        === END

        %<context>s
      TEXT

      ATTACK = <<~TEXT
        A restructure, proposed for problem %<problem_id>s (%<law>s) at %<path>s:
        operations: %<operations>s
        %<summary>s

        Decommission audit supplied by the proposal:
        %<audit>s

        Attack it. Verify every audit field independently: inspect reverse references and dynamic entrypoints; challenge every claim that a component is unused; inspect dependency manifests/lockfiles, registrations, generated paths and external/deploy consumers; confirm retained data and revival conditions. An INCONCLUSIVE dynamic or external path forbids deletion. Does it change behaviour, break a caller, a require, load order,
        or a Zeitwerk path and constant pair? Does it only move complexity around,
        or leave the tree harder to find one's way in? Does it merge code that only
        looks alike, whose units change for different reasons, or abstract fewer
        than three sites? Does it flatten depth that mirrors a real domain
        boundary? Does the old public import path survive? Compare the measured scorecard below with the baseline;
        each measured regression needs an operation-specific justification, while unmeasured dimensions stay inconclusive.
        A tie keeps the current tree. Approve only a change a maintainer would thank you for.
        Scorecard evidence: %<scorecard>s
        Answer with exactly one line: APPROVE: <evidence and reasons any measured regressions are acceptable>, or REJECT: <reason>.
        A bare APPROVE is invalid. If any measured regression lacks an operation-specific justification, reject.

        ```diff
        %<diff>s
        ```
      TEXT

      def initialize(agent:, repo_root:, bus: nil, restructure: nil, transformation_plan: nil,
                     ground_truth: nil, preserve_user_intent: nil, reference_graph: nil)
        @agent = agent
        @root = repo_root
        @bus = bus
        @reference_graph = reference_graph
        @transformation_plan = transformation_plan || TransformationPlan.new(root: Master::ROOT)
        @ground_truth = ground_truth
        @preserve_user_intent = preserve_user_intent
        @restructures = Hash.new do |cache, tree|
          cache[tree] = restructure || Restructure.new(
            repo_root:,
            tree:,
            ground_truth: @ground_truth,
            preserve_user_intent: @preserve_user_intent,
          )
        end
      end

      def run(target:, run_id:, phase: :normal)
        return [] if ENV["MASTER_FIX_RESTRUCTURES"] == "0"

        sweep_targets(target).flat_map do |tree_target|
          run_tree(
            tree_target,
            "#{run_id}-#{File.basename(tree_target)}",
            attempts: phase == :structure_first ? FIRST_ATTEMPTS : ATTEMPTS,
            rounds: phase == :structure_first ? FIRST_ROUNDS : ROUNDS,
            keeps: phase == :structure_first ? FIRST_KEEPS : KEEPS,
          )
        end
      end

      # Read-only structural planning used by --dry-run. It performs the same
      # deterministic finding clustering and candidate ordering as the live restructure
      # stage, but never asks the model, writes files, commits, or pushes.
      def preview(target:, run_id: "preview")
        ranked_candidate_map(candidates(target, run_id)).map do |row|
          problem = row.fetch(:problem)
          {
            problem_id: problem.id,
            files: problem.files.map { |path| relative(path) },
            laws: problem.laws,
            candidate_operations: problem.candidate_operations,
            primary_operation: problem.primary_operation,
            confidence: problem.confidence.to_s,
            payoff: row.fetch(:payoff),
            risk: row.fetch(:risk),
            payoff_risk: row.fetch(:ratio),
            evidence_hierarchy: @transformation_plan.evidence_hierarchy,
            domain_adapters: @transformation_plan.domain_adapters,
            smell_catalog: @transformation_plan.smell_catalog,
            refactoring_playbook: @transformation_plan.refactoring_playbook,
            reason: problem.reason,
          }
        end
      end

      def run_tree(target, run_id, attempts:, rounds:, keeps:)
        kept = []
        terminal = :limit_reached
        rounds.times do |round|
          break if kept.size >= keeps

          round_kept, terminal = run_round(target, "#{run_id}-#{round}", kept, attempts:, keeps:)
          kept.concat(round_kept)
          break if terminal

          Master::Trace::Dmesg.status("restructure0", "round #{round + 1}, kept #{round_kept.size}, total #{kept.size}")
          terminal = :limit_reached if kept.size >= keeps || round == rounds - 1
        end
        terminal = terminal_state(target, run_id, terminal, kept)
        Master::Trace::Dmesg.status("restructure0", "terminal=#{terminal} kept=#{kept.size}")
        @bus&.publish("fix_loop:restructure_exit", target: relative(target), state: terminal.to_s.upcase, kept: kept.size)
        kept
      end

      private

      # One sweep round: rank the round's candidates, try the top problems, and
      # return [round_kept, terminal]; terminal is nil while the sweep continues.
      def run_round(target, run_id, kept, attempts:, keeps:)
        ranked = ranked_candidate_map(candidates(target, run_id))
        return [[], :done] if ranked.empty?

        problems = ranked.map { |row| row.fetch(:problem) }
        round_kept, vetoes = try_candidates(problems.first(attempts), kept, candidate_map: render_candidate_map(ranked), keeps:)
        return [round_kept, round_terminal(problems, vetoes, attempts)] if round_kept.empty?

        [round_kept, nil]
      end

      # Try the ranked problems in order until one keeps or the keeps budget is
      # reached; count policy vetoes for the round's terminal decision.
      def try_candidates(problems, kept, candidate_map:, keeps:)
        round_kept = []
        vetoes = 0
        problems.each do |problem|
          break if kept.size + round_kept.size >= keeps

          result = attempt(problem, candidate_map:)
          round_kept << result.value! if result&.ok?
          break if result&.ok?
          vetoes += 1 if policy_veto?(result)
        end
        [round_kept, vetoes]
      end

      # A round that keeps nothing ends the sweep: more candidates than the
      # attempt budget allows is a budget stop, unanimous vetoes are a veto,
      # and anything else is a plateau.
      def round_terminal(problems, vetoes, attempts)
        if problems.size > attempts
          :limit_reached
        elsif vetoes.positive? && vetoes == problems.size
          :veto
        else
          :plateau
        end
      end

      # A sweep that stopped on its budget still ends cleanly when a final
      # read-only scan finds nothing left to restructure.
      def terminal_state(target, run_id, terminal, kept)
        return :done if terminal == :limit_reached && candidates(target, "#{run_id}-final").empty?

        terminal
      end

      def ask(prompt)
        @agent.ask(prompt, operation: :restructure).to_s
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "fix.restructure_sweep")
        ""
      end

      def relative(path) = path.to_s.delete_prefix("#{@root}/")
    end
  end
end
