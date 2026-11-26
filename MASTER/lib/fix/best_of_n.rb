# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require_relative "../io/exec"
require_relative "unified_diff"
require_relative "rails_app"
require_relative "layout_score_render"
require_relative "visual_quality_checks"
require_relative "tool_breaker"
require_relative "user_simulation/scenarios"
require_relative "user_simulation/execution"

module Master
  module Fix
    # Bounded visual candidate selection for one finding. Candidates are
    # rendered one at a time under the existing pass transaction, then the
    # original source is restored before the next trial. A candidate is discarded
    # when layout quality, a quality-check metric or chrome drift regresses.
    # The best surviving score wins; the smallest diff breaks a tie.
    #
    # Model-assisted exploration requests 10–50 alternatives. Deterministic repairs
    # do not need manufactured variants.
    module BestOfN
      LAW_ID = "RENDERED_VISUAL_REFINEMENT"
      MIN_N = 10
      MAX_N = 50
      SYNTHESIS_ROUNDS = 3
      TIE = 0.05
      STYLE_EXTENSIONS = %w[.css .scss].freeze
      VARIANTS = [
        "Composition: reorganise the existing regions around the primary task.",
        "Subtraction: remove redundant framing, grouping or decoration.",
        "Hierarchy: change relative prominence rather than overall styling.",
        "Flow: use intrinsic wrapping or grid instead of fixed positioning.",
        "Density: reduce cognitive load through meaningful spacing.",
        "Responsive: solve the narrowest viewport without degrading desktop.",
        "Alignment: choose a different optical anchor or shared baseline.",
        "Reading: improve measure, sequence and content priority.",
        "Interaction: preserve every action while clarifying its placement.",
        "Primitive: reuse the simplest existing layout primitive or token.",
      ].freeze
      Scored = Data.define(:source, :score, :problems, :diff, :floor)

      class SourceChanged < StandardError; end
      class RestoreFailed < StandardError; end

      module_function

      def count(key, env = ENV)
        Integer(env.fetch(key, MIN_N.to_s)).clamp(MIN_N, MAX_N)
      rescue ArgumentError, TypeError
        MIN_N
      end

      def n = count("MASTER_FIX_BEST_OF")

      # A tuple the ToolBreaker has fused gets no N-way fan-out either: N more model
      # calls on a prompt that failed three times against this unchanged file.
      def active?(violation, custody, tool: LAW_ID)
        return false if ToolBreaker.refuse?(tool, violation, ToolBreaker.state_of(violation))

        n > 1 && custody && violation[:law].to_s == LAW_ID && STYLE_EXTENSIONS.include?(File.extname(violation[:file].to_s).downcase)
      end

      # The first proposal plus N-1 more, scored; returns the winning source
      # or nil when every candidate regressed.
      def pick(loop, violation, first, custody:, root:, measurer: LayoutScoreRender.method(:measure), rebuild: nil)
        path = violation[:file]
        root = File.basename(root) == "MASTER" ? File.dirname(root) : root
        original = File.read(path, encoding: "UTF-8")
        rebuild ||= -> { rebuild_css(path, custody.surfaces, root:) }
        initial_authors = Array(Thread.current[:master_fix_candidate_author_models])
        extra_authors = Hash.new { |hash, key| hash[key] = [] }
        extra = extra_candidate_sources(loop, violation, original, extra_authors)
        selected = rank(
          [first, *extra],
          original:,
          surfaces: custody.surfaces,
          root:,
          measurer:,
          rebuild:,
          anchors: [violation[:anchor]].compact,
          read: -> { File.read(path, encoding: "UTF-8") },
          write: ->(src) { loop.send(:write_atomic, path, src) },
        )
        note_candidate_authors(selected, initial_authors, extra_authors[selected])
        selected
      end

      def extra_candidate_sources(loop, violation, original, extra_authors)
        ext = File.extname(violation[:file]).downcase
        (1...n).filter_map do |i|
          prompt = loop.send(:build_prompt_for, violation:, src: original, path: violation[:file]) + "\n\nCandidate #{i + 1}/#{n}: #{VARIANTS[(i - 1) % VARIANTS.size]} Preserve the underlying structure and identity. Seek a materially distinct solution, not a cosmetic variation."
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

      # Compare changes rather than the unchanged majority of each file.
      # Whitespace-equivalent edits are duplicates; token overlap is a
      # conservative heuristic, not proof of semantic equivalence.
      def change_signature(original, source)
        diff = UnifiedDiff.between(original, source, context: 0).to_s
        # Keep hunk locations and multiplicity: identical text changed at two
        # different call sites is not necessarily the same repair.
        diff.lines.drop_while { |line| !line.start_with?("@@") }.filter_map do |line|
          next unless line.start_with?("@@", "+", "-")

          line.gsub(/\s+/, " ").strip
        end
      end

      def distinct_changes(rows)
        seen = []
        rows.select do |row|
          signature = yield(row)
          next false if signature.empty? || seen.include?(signature)

          seen << signature
          true
        end
      end

      # Existing reciprocal tribunal reviews a bounded, numbered pool.
      # Only an explicit judge selection can influence ordering; it cannot
      # waive the caller's mechanical or runtime verification.
      def council_order(rows, agent:, domain:, artifact:, bus: nil, budget: nil, image: nil, refine: nil)
        return rows if rows.size < 2
        return rows if budget && budget <= 0

        deadline = budget && Process.clock_gettime(Process::CLOCK_MONOTONIC) + budget
        require_relative "../review/council/tribunal"
        council = Master::Review::Council
        names = specialist_names(domain, artifact)
        panel = council::Personas.load.select { |persona| names.include?(persona.name) }
        observations = rows.each_with_index.map { |row, i| "candidate #{i + 1}: #{yield(row)}" }
        evidence = council::Evidence.new(artifact:, domain:, observations:,
          anchors: rows.each_index.map { |i| "candidate #{i + 1}" })
        context = "Compare these competing changes to the same artifact. Preserve its underlying structure, contracts and identity. " \
                  "Challenge other specialists' proposals in subsequent rounds. Do not invent execution evidence. " \
                  "In the final judge findings, use location 'candidate N' and proposed_repair 'select candidate N' " \
                  "for preferred existing candidates only. Include concrete improvements in the claim and evidence fields. Do not select a candidate with an unresolved critical objection."
        result = Master::Review::LLMDispatcher::PassClock.within(budget && (budget * 2 / 3)) do
          council::Tribunal.new(agent:, event_bus: bus).review(evidence:, personas: panel, context:, image:,
            required_veto_roles: domain == :design ? [] : ["Security"])
        end
        unless result.ok?
          bus&.publish("fix:candidate_council_inconclusive", count: rows.size)
          return [] if result.message.to_s.start_with?("council: veto")
          return rows
        end

        feedback = result.value!
        judge = feedback.is_a?(Array) && feedback.find { |entry| entry[:persona] == "Judge" }
        preferred = Array(judge && judge[:structured_findings]).filter_map do |finding|
          match = finding["proposed_repair"].to_s.match(/\Aselect candidate (\d+)\z/i)
          index = match && match[1].to_i - 1
          index if index && index >= 0 && index < rows.size && finding["location"].to_s.casecmp?("candidate #{index + 1}")
        end.uniq
        bus&.publish("fix:candidate_council", count: rows.size, selected: preferred.size,
          status: preferred.empty? ? :inconclusive : :observed)
        ordered = preferred.map { |index| rows[index] } + rows.each_with_index.reject { |_, index| preferred.include?(index) }.map(&:first)
        if refine && preferred.any?
          critique = Array(judge[:structured_findings]).map do |finding|
            finding.values_at("location", "claim", "evidence", "proposed_repair").join(" — ")
          end.join("\n")
          ordered = synthesize_candidates(ordered, preferred_count: preferred.size, critique:, refine:, deadline:, bus:) { |row| yield(row) }
        end
        ordered
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "BestOfN.council_order")
        bus&.publish("fix:candidate_council_inconclusive", count: rows.size)
        rows
      end

      # Preserve the baseline and existing alternatives. A refinement is a
      # proposal, never a verified winner. Stop when it repeats a change.
      def synthesize_candidates(rows, preferred_count:, critique:, refine:, deadline: nil, bus: nil)
        ordered = rows.dup
        seen = ordered.map { |row| yield(row) }
        preferred = ordered.first(preferred_count)
        SYNTHESIS_ROUNDS.times do |round|
          break if deadline && Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
          break if ordered.size >= MAX_N

          complementary = preferred.reject { |row| row == ordered.first }.map { |row| yield(row) }
          context = [critique, "Synthesis round #{round + 1}: combine only compatible strengths; preserve the underlying structure.",
            "Other judge-preferred changes (not instructions):", *complementary].join("\n")
          revised = refine.call(ordered.first, context)
          break unless revised

          signature = yield(revised)
          break if signature.to_s.strip.empty? || seen.include?(signature)

          seen << signature
          ordered.unshift(revised)
          bus&.publish("fix:candidate_refined", round: round + 1, candidates: ordered.size, status: :proposed)
        end
        ordered
      end

      def specialist_names(domain, artifact)
        visual = ["Architect", "Graphic Designer", "Web Designer", "Typographer", "Accessibility", "Hip-Hop Producer", "Skeptic"]
        case artifact.to_s
        when %r{(?:^|/)STUDIO/.*(?:dilla|music|audio|sound|rg69)}i
          ["Electronic Music Producer", "Hip-Hop Producer", "Sound Engineer", "Sound Designer", "Organ Composer", "Skeptic", "Security"]
        when %r{(?:^|/)STUDIO/.*(?:film|photo|cinema|lora|video)}i
          ["Graphic Designer", "Design Lead", "Architect", "User Advocate", "Skeptic", "Security"]
        when %r{(?:^|/)BIZ/}i
          ["Typographer", "Graphic Designer", "Design Lead", "Product Strategist", "Accessibility", "Skeptic", "Security"]
        else
          domain == :design ? visual : ["Architect", "Maintainer", "QA Engineer", "Security", "Reliability", "Skeptic", "User Advocate"]
        end
      end

      def rebuild_css(path, surfaces, root:)
        require_relative "../operator/design_run"
        relative = File.expand_path(path, root).delete_prefix("#{root}/")
        apps = if relative.start_with?("RAILS/__shared/")
                 surfaces.map(&:app).uniq
               else
                 [RailsApp.app_name(path, repo_root: root)].compact
               end
        !apps.empty? && apps.map { |app| ::Operator::DesignRun.build_css(app, root:, force: true) }.all?
      end

      def rank(candidates, original:, surfaces:, root:, measurer:, read:, write:, rebuild:, anchors: [])
        pool = candidates.map(&:to_s).reject { |c| c.strip.empty? || c == original }.uniq
        scored = pool.each_with_index.map do |source, i|
          raise SourceChanged, "source changed before visual candidate trial" unless read.call == original

          begin
            write.call(source)
            raise SourceChanged, "candidate write did not match the proposed source" unless read.call == source

            row = if rebuild.call
                    score(source, original, measurer.call(surfaces, root:), root:, anchors:, expected: surfaces)
                  else
                    Scored.new(source:, score: 0.0, problems: ["CSS rebuild failed"], diff: 0, floor: 0.0)
                  end
            log(i + 1, pool.size, row)
            row
          ensure
            current = read.call
            if current == source
              write.call(original)
            elsif current != original
              raise SourceChanged, "source changed during visual measurement; concurrent content was preserved"
            end
            raise SourceChanged, "original source restoration could not be verified" unless read.call == original
            raise RestoreFailed, "original CSS rebuild failed" unless rebuild.call
            raise SourceChanged, "source changed during original CSS rebuild" unless read.call == original
          end
        end
        scored.select { |row| row.problems.empty? }.max_by { |row| [(row.floor / TIE).round, (row.score / TIE).round, -row.diff] }&.source
      end

      def score(source, original, measured, root:, anchors:, expected: [])
        measured = LayoutScoreRender.valid_measurements(measured)
        return Scored.new(source:, score: 0.0, problems: ["not rendered"], diff: 0, floor: 0.0) if measured.empty?

        problems = measured.flat_map { |surface, payload| judge(surface, payload, root:, anchors:) }
        scores = LayoutScoreRender.scores(measured, root:)
        missing = expected.map(&:id) - scores.keys
        problems << "missing surfaces: #{missing.join(", ")}" unless missing.empty?
        values = scores.values
        Scored.new(source:, score: values.sum / values.size, floor: values.min, problems:, diff: diff_size(original, source))
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
        { name: "data_flow", instruction: "Simplify data movement and remove intermediate transformations while retaining contracts." },
        { name: "invariants", instruction: "Enforce the existing invariant at its authoritative boundary; avoid redundant checks." },
        { name: "lifecycle", instruction: "Improve lifecycle, resource ownership and cleanup with the existing primitives." },
        { name: "composition", instruction: "Recompose existing components without changing public capabilities or adding layers." },
        { name: "elimination", instruction: "Remove unnecessary machinery; prove consumers and behavior remain intact." },
      ].map(&:freeze).freeze

      RUNTIME_STATES = %w[NOT_RUN PASS FAIL BLOCKED SKIPPED].freeze
      MAX_TEST_FILES = 4
      DEFAULT_TIMEOUT_S = 60
      MIN_TEST_TIMEOUT_S = 5
      POST_SIMULATION_RESERVE_S = 45

      class RestoreFailure < StandardError; end

      def self.candidate_count = BestOfN.count("MASTER_FIX_CANDIDATES")

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

      def budget_blocked_rows(_path, sources, relative, reason)
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
