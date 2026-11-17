# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require_relative "../io/exec"
require_relative "rails_app"
require_relative "layout_score_render"
require_relative "visual_quality_checks"
require_relative "tool_breaker"
require_relative "user_simulation/scenarios"
require_relative "user_simulation/execution"

module Master
  module Fix
    # Best-of-N for one visual finding, the way postpro keeps the best-scoring
    # of several drafts: the fixer proposes N distinct candidates, each is
    # written in turn, the affected surfaces are re-rendered and measured, and
    # the file goes back to its original before the next. A candidate is
    # discarded when its layout score drops past the tolerance, a quality-check
    # metric worsens, or chrome drifts off its budget. Of the survivors the
    # highest mean layout score wins, the smallest diff breaking a tie.
    #
    # MASTER_FIX_BEST_OF sets N (default 1). At 1 the pass is inactive and
    # RepairLoop behaves exactly as it did without it.
    module BestOfN
      LAW_ID = "RENDERED_VISUAL_REFINEMENT"
      MAX_N = 8
      TIE = 0.05
      STYLE_EXTENSIONS = %w[.css .scss].freeze
      VARIANTS = [
        "Candidate approach: change as little as possible, only the property the finding names.",
        "Candidate approach: reach the same goal through a different selector or property than the obvious one.",
        "Candidate approach: prefer an existing design token or layout primitive over a new value.",
      ].freeze
      Scored = Data.define(:source, :score, :problems, :diff)

      module_function

      def n = Integer(ENV.fetch("MASTER_FIX_BEST_OF", "1")).clamp(1, MAX_N)

      # A tuple the ToolBreaker has fused gets no N-way fan-out either: N more model
      # calls on a prompt that failed three times against this unchanged file.
      def active?(violation, custody, tool: LAW_ID)
        return false if ToolBreaker.refuse?(tool, violation, ToolBreaker.state_of(violation))

        n > 1 && custody && violation[:law].to_s == LAW_ID && STYLE_EXTENSIONS.include?(File.extname(violation[:file].to_s).downcase)
      end

      # The first proposal plus N-1 more, scored; returns the winning source
      # or nil when every candidate regressed.
      # The first proposal plus N-1 more, scored; returns the winning source
      # or nil when every candidate regressed.
      def pick(loop, violation, first, custody:, root:, measurer: LayoutScoreRender.method(:measure))
        path = violation[:file]
        root = File.basename(root) == "MASTER" ? File.dirname(root) : root
        original = File.read(path, encoding: "UTF-8")
        initial_authors = Array(Thread.current[:master_fix_candidate_author_models])
        extra_authors = Hash.new { |hash, key| hash[key] = [] }
        extra = extra_candidate_sources(loop, violation, original, extra_authors)
        selected = rank([first, *extra], original:, surfaces: custody.surfaces, root:, measurer:, anchors: [violation[:anchor]].compact,
                        write: ->(src) { loop.send(:write_atomic, path, src) })
        note_candidate_authors(selected, initial_authors, extra_authors[selected])
        selected
      end

      def extra_candidate_sources(loop, violation, original, extra_authors)
        ext = File.extname(violation[:file]).downcase
        (1...n).filter_map do |i|
          prompt = loop.send(:build_prompt_for, violation:, src: original, path: violation[:file]) + "\n\n#{VARIANTS[(i - 1) % VARIANTS.size]}"
          Thread.current[:master_llm_answer_model] = nil
          raw = loop.send(:ask_agent, prompt, image: loop.instance_variable_get(:@visual_image)).to_s
          candidate = loop.send(:extract_code, raw, ext)
          author = Thread.current[:master_llm_answer_model]
          extra_authors[candidate] << author if candidate && !author.to_s.empty?
          candidate
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "BestOfN.candidate") if defined?(Master::Ground::Swallow)
          nil
        end
      end

      def note_candidate_authors(selected, initial_authors, selected_authors)
        return unless selected

        Thread.current[:master_fix_candidate_author_models] =
          (initial_authors + Array(selected_authors)).compact.map(&:to_s).reject(&:empty?).uniq.freeze
      end

      def rank(candidates, original:, surfaces:, root:, measurer:, write:, anchors: [])
        pool = candidates.map(&:to_s).reject { |c| c.strip.empty? || c == original }.uniq
        scored = pool.each_with_index.map do |source, i|
          write.call(source)
          row = score(source, original, measurer.call(surfaces, root:), root:, anchors:)
          log(i + 1, pool.size, row)
          row
        ensure
          write.call(original)
        end
        scored.select { |row| row.problems.empty? }.max_by { |row| [(row.score / TIE).round, -row.diff] }&.source
      end

      def score(source, original, measured, root:, anchors:)
        return Scored.new(source:, score: 0.0, problems: ["not rendered"], diff: 0) if measured.empty?

        problems = measured.flat_map { |surface, payload| judge(surface, payload, root:, anchors:) }
        mean = LayoutScoreRender.scores(measured, root:).values
        Scored.new(source:, score: (mean.sum / mean.size).round(1), problems:, diff: diff_size(original, source))
      end

      def judge(surface, payload, root:, anchors:)
        base = VisualQualityChecks.load(root, surface)
        cur = VisualQualityChecks.measure(surface, payload, baseline_rects: base && base["rects"])
        worse = base ? VisualQualityChecks.worse(base, cur) : []
        drift = VisualDriftBudget.check(surface, payload, root:, anchors:)
        worse + LayoutScoreStore.judge(surface, payload, root:) + (drift.empty? ? [] : ["chrome drift #{drift.first(2).join(", ")}"])
      end

      def diff_size(a, b)
        old = a.lines
        (b.lines - old).size + (old - b.lines).size
      end

      def log(index, total, row)
        verdict = row.problems.empty? ? "kept" : "discarded: #{row.problems.first(2).join("; ")}"
        Master::Trace::Dmesg.status("best0", "candidate #{index}/#{total} score #{row.score} diff #{row.diff} #{verdict}")
      rescue StandardError
        nil
      end
    end

    # Shared candidate simulator for /fix: scenario oracles select existing
    # focused tests, and only measured command results count as evidence. It lives
    # beside BestOfN so the repository retains one existing candidate-selection owner.
    class UserSimulation
      APPROACHES = [
        {
          name: "minimal",
          instruction: "Solve the exact finding with the smallest local change. Preserve public behavior, surrounding structure and unrelated code. Do not add a new abstraction or file unless the existing owner cannot express the repair.",
        },
        {
          name: "root_cause",
          instruction: "Solve the underlying cause at its natural owner, not merely the visible symptom. Trace callers, state transitions and failure boundaries. Keep the interface stable unless a verified contract requires a change.",
        },
        {
          name: "reuse_and_simplify",
          instruction: "Look for an existing abstraction, invariant, helper or token that can own the fix. Prefer removing duplicate decisions or simplifying the flow over adding a wrapper. Preserve all unrelated behavior.",
        },
        {
          name: "failure_first",
          instruction: "Start from the most consequential counterexample and make the failure explicit and recoverable. Cover invalid input, duplicate submissions, stale state and partial failure without widening the change.",
        },
        {
          name: "structural",
          instruction: "Consider a materially different boundary or transformation from the other candidates. Keep the change reversible, retain compatibility, and reject a refactor that merely relocates complexity.",
        },
      ].map(&:freeze).freeze

      RUNTIME_STATES = %w[NOT_RUN PASS FAIL BLOCKED SKIPPED].freeze
      MAX_TEST_FILES = 4
      DEFAULT_TIMEOUT_S = 60
      MIN_TEST_TIMEOUT_S = 5
      POST_SIMULATION_RESERVE_S = 45

      class RestoreFailure < StandardError; end

      def self.candidate_count
        Integer(ENV.fetch("MASTER_FIX_CANDIDATES", "3")).clamp(2, APPROACHES.length)
      rescue ArgumentError
        3
      end

      def self.approach(index)
        APPROACHES.fetch(index % APPROACHES.length)
      end

      def initialize(root: Master::REPO_ROOT, campaign_path: nil, bus: nil, runner: nil, timeout: nil, deadline: nil)
        @root = File.expand_path(root)
        @campaign_path = campaign_path || File.join(
          Master::REPO_ROOT, "RAILS", "test", "interaction_campaign_400.json"
        )
        @bus = bus
        @runner = runner
        @timeout = (timeout || test_timeout).to_i.clamp(MIN_TEST_TIMEOUT_S, 300)
        @deadline = deadline
        @campaign = nil
      end


      # The RAILS tree answers for itself; a RAILS path never falls through
      # to the MASTER patterns.


      # Test paths are run in a test bundle with bounded timeouts. The output
      # is summarized to a fingerprint; candidate selection never needs to log
      # raw test output, which may contain user data or secrets.
      # Test paths are run in a test bundle with bounded timeouts. The output
      # is summarized to a fingerprint; candidate selection never needs to log
      # raw test output, which may contain user data or secrets.
      def evaluate_candidates(path:, original:, candidates:, writer:, deadline: @deadline)
        @deadline = deadline
        path = File.expand_path(path.to_s, @root)
        sources = Array(candidates).map(&:to_s)
        return [] if sources.empty?

        relative = relative_path(path)
        return outside_boundary_rows(path, sources) unless relative

        tests = test_paths_for(path)
        return result_rows(sources, :unavailable, "no focused test path exists for this surface") if tests.empty?

        @commands_remaining = tests.length * (sources.length + 1)
        # Assign first: a bare `reason` earlier in the same statement would
        # parse as the reason(error) method call, not this local.
        blocked_reason = budget_block_reason
        return budget_blocked_rows(path, sources, relative, blocked_reason) if blocked_reason

        with_simulation_lock { evaluate_candidates_locked(path:, original:, sources:, tests:, writer:, relative:) }
      rescue RestoreFailure
        raise
      rescue StandardError => e
        publish("repair_loop:user_simulation_blocked", path: path.to_s, reason: reason(e))
        result_rows(sources, :blocked, reason(e))
      end

      def outside_boundary_rows(path, sources)
        publish(
          "repair_loop:user_simulation_blocked",
          path: path.to_s,
          reason: "target must be a regular, non-symlink file inside the repository",
        )
        result_rows(sources, :blocked, "target is outside the safe regular-file boundary")
      end

      def budget_blocked_rows(path, sources, relative, reason)
        publish("repair_loop:candidate_simulation_blocked", path: relative, reason:)
        result_rows(sources, :blocked, reason)
      end

      def evaluate_candidates_locked(path:, original:, sources:, tests:, writer:, relative:)
        disk_source = File.read(path, encoding: "UTF-8")
        unless disk_source == original
          publish("repair_loop:user_simulation_blocked", path: relative, reason: "target source changed since proposal generation")
          return result_rows(sources, :blocked, "target source changed since proposal generation")
        end

        baseline = tests.map { |test_path| execute_test(test_path) }
        verify_unchanged_source!(path, original, relative, "focused baseline tests")
        sources.map do |source|
          simulate_candidate(path:, original:, source:, tests:, baseline:, writer:, relative:)
        end
      end

      def simulate_candidate(path:, original:, source:, tests:, baseline:, writer:, relative:)
        candidate_results = nil
        row = nil
        begin
          verify_unchanged_source!(path, original, relative, "candidate write")
          writer.call(path, source)
          written_source = File.read(path, encoding: "UTF-8")
          raise IOError, "candidate source differs from the requested write" unless written_source == source

          candidate_results = tests.map { |test_path| execute_test(test_path) }
          row = compare(baseline, candidate_results, tests)
        rescue RestoreFailure
          raise
        rescue StandardError => e
          row = result(:blocked, tests, baseline, candidate_results || [], reason(e))
        ensure
          restore_candidate_source!(path:, original:, source:, writer:, relative:)
        end
        publish_simulation(path:, relative:, row:, tests:)
        row
      end

      # The trial wrote its candidate over the original; put the operator's
      # content back exactly, refusing to overwrite anything else that landed
      # meanwhile.
      def restore_candidate_source!(path:, original:, source:, writer:, relative:)
        begin
          current_source = File.read(path, encoding: "UTF-8")
          if current_source == source
            writer.call(path, original)
          elsif current_source != original
            raise RestoreFailure, "source changed during simulation; refusing to overwrite concurrent content"
          end
          restored_source = File.read(path, encoding: "UTF-8")
          raise IOError, "restored source differs from the original snapshot" unless restored_source == original
        rescue RestoreFailure => e
          publish("repair_loop:user_simulation_restore_failed", path: relative, error: reason(e))
          raise
        rescue StandardError => e
          publish("repair_loop:user_simulation_restore_failed", path: relative, error: reason(e))
          raise RestoreFailure, "candidate simulation could not verify restoration of #{relative}: #{e.class}: #{e.message}"
        end
      end

      def publish_simulation(path:, relative:, row:, tests:)
        publish(
          "repair_loop:candidate_simulation",
          path: relative,
          surfaces: surfaces_for(path),
          scenario_oracles_consulted: campaign.fetch("cases").count { |item| surfaces_for(path).include?(item.fetch("surface_id")) },
          scenario_runtime_status: "NOT_RUN",
          tests:,
          status: row.fetch(:status),
          regressions: row.fetch(:regressions).length,
          improvements: row.fetch(:improvements).length,
        )
      end

      private

      def self.rank(status)
        {
          pass: 0,
          improved: 1,
          no_regression: 2,
          unavailable: 3,
          blocked: 4,
          regression: 5,
        }.fetch(status.to_sym, 4)
      end

      private


      # Candidate trials share RepairLoop's per-file deadline. Reserve time
      # for the independent verifier and consensus check, then divide only the
      # remaining time across commands still to run. This keeps timeouts from
      # interrupting the reversible source transaction during unwinding.


    end

  end
end
