# frozen_string_literal: true
require "json"
require "digest"
require "set"
require_relative "ux_refinement_catalog"
require_relative "morphological_score"
require_relative "architecture_exploration/persistence"
require_relative "architecture_exploration/exploration"
require_relative "architecture_exploration/candidates"
require_relative "architecture_exploration/reporting"

module Master
  module Fix
    # The planning-only architecture tournament. This file is the class owner:
    # the contract below, the eligible-tree selection and the run
    # orchestration. The architecture_exploration/ parts re-open the same
    # class for saved-report persistence, per-tree exploration and evidence
    # grounding, candidate intake/scoring, and brief rendering.
    class ArchitectureExploration
      TREE_NAMES = MasterPaths::TREES
      REPORT_FIELDS = %w[tree status requested accepted qualified decision winner shortlist rejections candidates evidence_manifest].freeze
      DEFAULT_CANDIDATES = 36
      MIN_CANDIDATES = 30
      MAX_CANDIDATES = 40
      SCORES = { source_evidence: 20, test_anchors: 18, verification: 15, rollback: 15, scope: 12, law_alignment: 10, tradeoff_analysis: 10 }.freeze
      MIN_WINNER_SCORE = 65
      MIN_QUALIFIED_CANDIDATES = 3
      QUALITY_FLOORS = { source_evidence: 12, test_anchors: 9, verification: 8, rollback: 7, law_alignment: 5, tradeoff_analysis: 4 }.freeze
      LENSES = ["AX01|Keep current boundaries|Harden the smallest proven weak seam.",
"AX02|Functional core and imperative shell|Separate deterministic decisions from I/O.",
"AX03|Explicit state machine|Make lifecycle transitions explicit.",
"AX04|Ports and adapters|Separate domain contracts from adapters.",
"AX05|Modular monolith|Group cohesive capabilities without distributed overhead.",
"AX06|Microkernel with capabilities|Keep a small kernel and typed extensions.",
"AX07|Event log and projections|Use events where replay is justified.",
"AX08|Durable workflow checkpoints|Make long-running tasks resumable.",
"AX09|Transactional ownership|One owner handles mutation and rollback.",
"AX10|Immutable plan and evidence ledger|Bind plans to evidence.",
"AX11|Declarative manifests|Declare checks and commands once.",
"AX12|Explicit pipeline stages|Define stages and failure states.",
"AX13|Dependency graph scheduler|Order work by dependencies.",
"AX14|Data-oriented flat core|Prefer immutable data.",
"AX15|Typed outcomes and errors|Prevent failure from looking successful.",
"AX16|Reducer-owned state|One reducer owns state transitions.",
"AX17|Single-writer ownership|Give each mutable artifact one writer.",
"AX18|Read models for observation|Keep projections read-only.",
"AX19|Policy-mechanism separation|Keep laws separate from mechanisms.",
"AX20|Metadata-driven commands|Generate help and completion from metadata.",
"AX21|Incremental verified caching|Cache evidence with fingerprints.",
"AX22|Generated artifact ownership|Regenerate outputs and reject drift.",
"AX23|Contract-first adapters|Define interface contracts and tests.",
"AX24|Typed intermediate representation|Normalize findings before repair.",
"AX25|Staged compiler pipeline|Parse, validate, plan, emit and verify.",
"AX26|Unified resource budget|Share deadline across the operation.",
"AX27|Proof-carrying changes|Bind changes to evidence and rollback.",
"AX28|Fault-containment boundaries|Report partial failures explicitly.",
"AX29|Least-authority executor|Give executors narrow capabilities.",
"AX30|Deterministic fast path|Use deterministic transforms first.",
"AX31|Capability-aware model router|Use live capability and health.",
"AX32|Evidence-scored candidate tournament|Rank plans using evidence.",
"AX33|Compatibility facade and strangler|Replace one verified seam at a time.",
"AX34|Delete and consolidate|Remove duplication before adding abstractions.",
"AX35|Replayable simulation harness|Replay failure scenarios.",
"AX36|Narrow vertical slices|Change one complete path at a time.",
"AX37|Shared-nothing workers|Isolate workers only when justified.",
"AX38|Explicit concurrency ownership|Make concurrency boundaries explicit.",
"AX39|Versioned data contracts|Version data and rollback contracts.",
"AX40|Composition-root wiring|Centralize wiring without hidden globals."].map do |entry|
        id, name, intent = entry.split("|", 3)
        { id:, name:, intent: }.freeze
      end.freeze

      def self.candidate_count(env = ENV)
        Integer(env.fetch("MASTER_FIX_ARCHITECTURE_CANDIDATES", "36")).clamp(30, 40)
      rescue ArgumentError, TypeError
        36
      end

      def self.contract
        { "version" => 2, "trees" => TREE_NAMES, "default_candidates_per_tree" => 36,
          "minimum_candidates_for_selection" => 30, "maximum_candidates_per_tree" => 40,
          "score_weights" => SCORES, "model_scores" => "ignored",
          "quality_gate" => { "minimum_score" => MIN_WINNER_SCORE, "minimum_qualified_candidates" => MIN_QUALIFIED_CANDIDATES,
            "dimension_floors" => QUALITY_FLOORS },
          "required_consequence_fields" => %w[benefits tradeoffs risks],
          "diversity_gate" => "reject highly similar plans, especially when they target nearly identical path sets",
          "mutation" => "planning_only; selected architecture never authorizes a rewrite",
          "persistence" => "checksum_verified per-run revisions; reuse only complete tree rows whose provenance still matches",
          "execution_evidence" => "NOT_RUN until actual tree verification commands execute" }
      end

      def initialize(root:, agent:, bus: nil, candidate_count: nil, run_journal: nil, run_id: nil, provenance: nil,
                     dependency_tangles: [], antigens: [], source_digests: {})
        @root = File.expand_path(root)
        @agent = agent
        @bus = bus
        @run_journal = run_journal
        @run_id = run_id.to_s
        @provided_provenance = provenance
        @dependency_tangles = Array(dependency_tangles).freeze
        @antigens = Array(antigens).freeze
        @source_digests = source_digests.is_a?(Hash) ? source_digests.transform_keys(&:to_s).freeze : {}.freeze
        @count = Integer(candidate_count || self.class.candidate_count).clamp(30, 40)
      rescue ArgumentError, TypeError
        @count = DEFAULT_CANDIDATES
      end

      def self.eligible_targets(root:, target:)
        base = File.expand_path(root)
        base_real = File.realpath(base)
        selected = File.expand_path(target, base)
        if selected == base || selected == base_real
          TREE_NAMES.map { |name| File.join(base, name) }.select do |path|
            !File.symlink?(path) && File.directory?(path) && real_path_inside?(path, base_real)
          end
        elsif TREE_NAMES.include?(File.basename(selected)) && File.dirname(selected) == base &&
              !File.symlink?(selected) && File.directory?(selected) && real_path_inside?(selected, base_real)
          [selected]
        else
          []
        end
      rescue SystemCallError, ArgumentError
        []
      end

      def self.real_path_inside?(path, root)
        value = File.realpath(path)
        base = File.realpath(root)
        value == base || value.start_with?(base + File::SEPARATOR)
      rescue SystemCallError, ArgumentError
        false
      end

      def run(target:, files:)
        trees = self.class.eligible_targets(root: @root, target:)
        return { "status" => "SKIPPED", "targets" => [], "brief" => "" } if trees.empty?

        current_provenance = provenance
        previous = saved_report
        return resumed_report(previous, target, trees, current_provenance) if reusable_complete_report?(previous, target, trees, current_provenance)

        explore_all_trees(target:, trees:, files:, previous:, provenance: current_provenance)
      rescue StandardError => error
        publish("fix_loop:architecture_exploration_inconclusive",
          target: relative_target(target), reason: safe_reason(error), error_class: error.class.name)
        report = inconclusive_run_report(target:, error:,
          provenance: (defined?(current_provenance) ? current_provenance : provenance),
          rows: (defined?(rows) && rows.is_a?(Hash) ? rows : {}))
        persist_inconclusive_report(target:, trees: (defined?(trees) ? trees : []),
          rows: (defined?(rows) && rows.is_a?(Hash) ? rows : {}),
          report:) if trees && !trees.empty? && !@persistence_blocked
        report
      end

      private

      # Reuse complete tree rows from the saved report, then explore the
      # remaining trees; state is persisted RUNNING after every tree so an
      # interrupted run leaves resumable, provenance-matched partial state.
      def explore_all_trees(target:, trees:, files:, previous:, provenance:)
        rows = {}
        reusable_tree_rows(previous, target, trees, provenance).each { |name, row| rows[name] = row }
        persist_report(target:, trees:, rows:, status: "RUNNING", provenance:)
        trees.each do |tree|
          rows[File.basename(tree)] ||= explore(tree, files)
          persist_report(target:, trees:, rows:, status: "RUNNING", provenance:)
        end
        report = aggregate_report(target:, trees:, rows:, provenance:)
        persist_report(target:, trees:, rows:, status: report.fetch("status"), provenance:, final_report: report)
        report
      end

      # A complete, provenance-matched saved report is reused verbatim: the
      # tournament already ran for exactly these source bytes.
      def resumed_report(previous, target, trees, current_provenance)
        publish("fix_loop:architecture_exploration_resumed",
                target: relative_target(target), trees: trees.size, source_digest: current_provenance["source_digest"])
        previous
      end

      # The run-level answer when anything raised: planning continues as
      # ordinary /fix, with whatever complete rows already persisted.
      def inconclusive_run_report(target:, error:, provenance:, rows: {})
        {
          "schema_version" => 2,
          "status" => "INCONCLUSIVE",
          "target" => relative_target(target),
          "provenance" => provenance,
          "targets" => rows.values,
          "brief" => "ARCHITECTURE EXPLORATION INCONCLUSIVE: #{error.class}: #{safe_reason(error)}. Continue ordinary /fix.",
          "requested_candidates_per_tree" => @count,
        }
      end

      def persist_inconclusive_report(target:, trees:, rows:, report:)
        persist_report(target:, trees:, rows:, status: "INCONCLUSIVE", provenance: report.fetch("provenance"), final_report: report)
      rescue StandardError => persist_error
        publish("fix_loop:architecture_report_persistence_failed",
                reason: safe_reason(persist_error), error_class: persist_error.class.name)
      end

      def publish(event, payload)
        @bus&.publish(event, payload)
      rescue StandardError
        nil
      end
    end
  end
end
