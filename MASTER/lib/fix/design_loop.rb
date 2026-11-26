# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "json"
require "securerandom"
require_relative "../io/exec"
require_relative "transaction"
require_relative "design_edit"
require_relative "best_of_n"
require_relative "design_prompts"
require_relative "layout_score_render"
require_relative "visual_quality_checks"
require_relative "../review/council/evidence"
require_relative "repair_outcomes"
require "digest"

module Master
  module Fix
    # The loop other agents use for interface work, with MASTER's own measures:
    # look at the weakest surface, ask a vision model for ONE layout edit to a
    # stylesheet, apply it, re-render, and keep the edit only if the surface
    # scored higher and nothing else got worse; otherwise undo it. Each kept edit
    # is its own commit. A surface that stops improving is set aside.
    #
    # Every outside effect is injected (browser, model, CSS build, git) so the
    # loop's decisions are testable without Chrome or a model.
    class DesignLoop
      include DesignPrompts

      TIE = 0.05
      OTHERS_TOLERANCE = 1.0
      TRIES_PER_SURFACE = DesignPrompts::VARIANTS.size
      SHARED = "/RAILS/__shared/"
      MARKUP_FILES = 2
      MAX_CANDIDATE_FILES = 4
      Candidate = Data.define(:edits, :why) do
        def files = edits.map(&:file)
        def key = edits.map(&:key).sort
        def markup? = edits.all?(&:markup?)
      end
      Round = Data.define(:number, :surface, :why, :outcome, :before, :after)

      # What the loop works on and how long.
      Plan = Data.define(:surfaces, :root, :rounds, :candidates)

      # Everything outside: measure ->(surfaces) { [[surface, payload, shot], ...] };
      # ask ->(prompt, image) { reply }; build ->(app) { ok }; commit_file ->(path, message, transaction) { delivered };
      # sources_for ->(surface) { [stylesheet paths] }; guard ->(path, new_text) { refusal or nil }.
      World = Data.define(:measure, :ask, :build, :commit_file, :sources_for, :guard, :council) do
        def initialize(measure:, ask:, build:, commit_file:, sources_for:, guard:, council: nil) = super
      end

      def initialize(plan:, world:, say: ->(_) {})
        @plan = plan
        @world = world
        @say = say
        @rejected = []
        @undone = []
        @judged = 0
        @spent = Hash.new(0)
        @variant_cursor = Hash.new(0)
      end

      def run
        recover_design_transactions!
        @state = measured(@plan.surfaces)
        raise "design baseline incomplete" unless complete_capture?(@plan.surfaces, @state)
        survey
        results = []
        @plan.rounds.times do |index|
          break unless (@target = weakest)

          results << attempt(index + 1)
        end
        results
      end

      private

      def measured(surfaces)
        @world.measure.call(surfaces).filter_map { |surface, payload, shot| row(surface:, payload:, shot:) }
      end

      def row(surface:, payload:, shot:)
        return unless LayoutScoreRender.valid_payload?(payload)

        value = score(payload)
        return unless value.is_a?(Numeric) && value.real? && value.finite?
        return unless shot && File.file?(shot) && File.size(shot).positive?

        found = VisualQualityChecks.measure(surface, payload)["offenders"]
        counts = found.transform_values(&:size).reject { |_, count| count.zero? }
        { surface:, payload:, shot:, score: value, shot_sha256: Digest::SHA256.file(shot).hexdigest,
          offenders: counts, offender_keys: found.reject { |_, keys| keys.empty? } }
      end

      def complete_capture?(surfaces, rows)
        expected = surfaces.map(&:id).sort
        actual = rows.map { |row| row[:surface].id }.sort
        expected == actual && actual.uniq == actual
      end

      def score(payload) = LayoutScoreStore.measure(@plan.root, payload).score

      # Sparse compositions deserve review too; only pages without editable anchors are skipped.
      def weakest
        open = @state.reject { |row| @spent[row[:surface].id] >= TRIES_PER_SURFACE || sparse?(row) }
        open.min_by { |row| row[:score] }
      end

      def sparse?(row) = page_tokens_of(row).empty?

      def survey
        @state.each do |row|
          note = sparse?(row) ? ", no editable anchors" : ""
          @say.call("#{row[:surface].id}: score #{row[:score].round(1)}, #{page_tokens_of(row).size} classes and ids#{note}")
        end
      end

      def attempt(number)
        return give_up(number) unless refresh

        Dir.mktmpdir("master-design-") do |directory|
          pool = candidates
          accepted = pool.each_with_index.filter_map { |edit, index| trial(edit, capture: File.join(directory, "#{index}.png")) }
          @say.call("candidate verification: #{pool.size} tried, #{accepted.size} qualified, #{pool.size - accepted.size} not qualified")
          best = accepted.reduce { |left, right| prefer_candidate(left, right) }
          return give_up(number) unless best

          keep(number, best)
        end
      end

      # A fresh baseline for the target and its guards at the start of every round. A
      # score taken minutes ago, or cold, is not comparable with one taken after an edit,
      # and that gap once passed for an improvement.
      def refresh
        surfaces = guards.map { |row| row[:surface] }
        fresh = measured(surfaces)
        return false unless complete_capture?(surfaces, fresh)

        target = fresh.find { |row| row[:surface].id == @target[:surface].id }
        return false unless target

        @fresh = fresh
        @target = target
        @page_tokens = page_tokens_of(@target)
        keep_before_shot
        @noise = noise
        return false unless @noise

        @experiment = SecureRandom.hex(16)
        merge(@fresh)
        true
      end

      # A failed second capture is unknown noise, not zero noise.
      def noise
        surfaces = [@target[:surface]]
        rows = measured(surfaces)
        return unless complete_capture?(surfaces, rows)

        (rows.first[:score] - @target[:score]).abs
      end

      def margin = [TIE, 2 * @noise.to_f].max

      # Re-rendering overwrites the screenshot, so the picture the vision check
      # compares against is copied aside first.
      def keep_before_shot
        @before_shot = @target[:shot].sub(/\.png\z/, ".before.png")
        FileUtils.cp(@target[:shot], @before_shot)
      end

      def give_up(number)
        @spent[@target[:surface].id] += 1
        @say.call("no qualifying improvement in this round; not proof of global convergence")
        round(number:, why: "no usable edit", outcome: :none, after: @target[:score])
      end

      def candidates
        offered = Array(@world.sources_for.call(@target[:surface]))
        views, sheets = offered.partition { |path| path.end_with?(".erb") }
        sources = sheets.first(4) + views.first(MARKUP_FILES)
        id = @target[:surface].id
        start = @variant_cursor[id]
        @variant_cursor[id] += @plan.candidates
        generated = Array.new(@plan.candidates) { |variant| propose(sources, start + variant) }.compact
        distinct = BestOfN.distinct_changes(generated) do |candidate|
          candidate_signature(candidate)
        end
        @say.call("candidate exploration: requested #{@plan.candidates}, generated #{generated.size}, distinct #{distinct.size}")
        return distinct unless @world.council

        reviewed = @world.council.call(distinct, @target, lambda do |candidate, critique|
          context = candidate.edits.map { |edit| "#{edit.file}: #{edit.proposal.find} -> #{edit.proposal.replace}" }.join("\n")
          propose(sources, start, feedback: "Selected proposal:\n#{context}\nCouncil critique (advisory):\n#{critique}\nProduce one materially improved candidate against the unchanged source.")
        end)
        BestOfN.distinct_changes(reviewed) do |candidate|
          candidate_signature(candidate)
        end.first(BestOfN::MAX_N)
      end

      def candidate_signature(candidate)
        candidate.edits.flat_map do |edit|
          proposal = edit.proposal
          BestOfN.change_signature(proposal.find, proposal.replace).map { |line| [edit.file, line] }
        end.sort
      end

      def propose(sources, variant, feedback: nil)
        request = [prompt(sources, variant), feedback].compact.join("\n\n")
        reply = @world.ask.call(request, [@target[:shot]])
        rules = DesignEdit::Rules.new(guard: @world.guard, scale: nil, type_scale: type_steps, classes: sheet_classes(sources))
        candidate = parse_candidate(reply, sources, rules)
        raise DesignEdit::Refused, "already tried and undone" if @rejected.include?(candidate.key)

        candidate.edits.each { |edit| refuse_unseen_selector!(edit) }
        refuse_lone_shared!(candidate)
        candidate
      rescue DesignEdit::Refused, StandardError => e
        @say.call("#{@target[:surface].id}: edit not usable, #{e.message.lines.first.to_s.strip}")
        nil
      end

      def parse_candidate(reply, sources, rules)
        data = JSON.parse(reply.to_s[/\{.*\}/m].to_s)
        rows = data.key?("edits") ? data["edits"] : [data]
        unless rows.is_a?(Array) && rows.size.between?(1, MAX_CANDIDATE_FILES) && rows.all? { |row| row.is_a?(Hash) }
          raise DesignEdit::Refused, "candidate must contain one to #{MAX_CANDIDATE_FILES} file edits"
        end

        why = data["why"].to_s.strip
        raise DesignEdit::Refused, "candidate needs a design rationale" if why.empty?

        edits = rows.map { |row| DesignEdit.parse(JSON.generate(row.merge("why" => why)), allowed: sources, rules:) }
        edits.each(&:check!)
        files = edits.map(&:file)
        raise DesignEdit::Refused, "candidate repeats a file" unless files.uniq.size == files.size

        Candidate.new(edits:, why:)
      end

      # An edit to a rule that matches nothing on the page changes nothing the judges can
      # see, so it is refused before it costs a render.
      def refuse_unseen_selector!(edit)
        tokens = edit.selector_tokens
        return if @page_tokens.empty?

        if tokens.empty?
          raise DesignEdit::Refused, edit.markup? ? "its element has no class to find it by on the page" : "its rule names no class or id, so it applies across the app"
        end
        return if (tokens & @page_tokens).any?

        raise DesignEdit::Refused, "its selector (#{tokens.first(3).join(' ')}) is not on this page"
      end

      # A stylesheet under RAILS/__shared reaches every app that imports it, so an edit there
      # is judged on every app the run measures; a run that measures one app cannot judge it.
      def refuse_lone_shared!(edit)
        return unless shared?(edit) && measured_apps.size < 2

        raise DesignEdit::Refused, "it is in a stylesheet shared across apps and this run measures only " \
                                   "#{measured_apps.first}; name more apps with --app"
      end

      def shared?(candidate) = candidate.files.any? { |file| file.include?(SHARED) }

      def measured_apps = @state.map { |row| row[:surface].app }.uniq

      # Rebuilds the CSS the edit can change: the target's app, or every measured app for a
      # shared stylesheet, so the guards are measured against the edit and not a stale build.
      def rebuild(edit)
        return true if edit.markup?

        apps = shared?(edit) ? measured_apps : [@target[:surface].app]
        apps.map { |app| @world.build.call(app) }.all?
      end

      # The class names the offered stylesheets define: what a view edit may add to an element.
      def sheet_classes(sources)
        sheets = sources.reject { |path| path.end_with?(".erb") }
        sheets.flat_map { |path| File.read(path, encoding: "UTF-8").scan(/\.([A-Za-z_][\w-]*)/).flatten }.uniq
      end

      # The declared text sizes a font-size may take: the token scale at or above the
      # body minimum, so a size cannot be chosen by shrinking text to fit a measure.
      def type_steps
        declared = LayoutScoreStore.tokens(@plan.root).font.map(&:px)
        return declared if declared.empty?

        minimum = Master::Design::Typography.profile(:social, root: File.join(@plan.root, "MASTER")).fetch(:minimum_body_px)
        declared.select { |px| px >= minimum }
      end

      # The classes and ids the walk found on the page.
      def page_tokens_of(row)
        Array(row[:payload]["elements"]).flat_map { |element| element["key"].to_s.scan(/[.#][\w-]+/) }.uniq
      end

      # Every temporary source mutation is a durable transaction. A process
      # exit during measurement leaves an open manifest that the next design
      # run or /fix can recover, rather than an unowned candidate in the tree.
      def trial(edit, capture: nil)
        transaction = nil
        candidate = nil
        verdict = nil
        begin
          transaction = begin_candidate_transaction(edit)
          apply_candidate!(transaction, edit)
          if rebuild(edit)
            after = measured(@fresh.map { |row| row[:surface] })
            verdict = judge(@fresh, after)
            @say.call("#{@target[:surface].id}: #{edit.why} -> #{verdict[:text]}")
            if verdict[:ok]
              target = after.find { |row| row[:surface].id == @target[:surface].id }
              FileUtils.cp(target.fetch(:shot), capture) if capture
              candidate = {
                capture:,
                edit:, gain: verdict[:gain], after:,
                source_hash: source_hashes(transaction, edit),
                candidate_hash: observed_hashes(transaction, edit),
              }
            else
              @rejected << edit.key
              @undone << "#{edit.why} (#{verdict[:text]})"
            end
          end
        rescue DesignEdit::Refused => e
          @say.call("#{@target[:surface].id}: edit refused, #{e.message}")
        ensure
          if transaction
            cleanup = restore_candidate_transaction(transaction, edit)
            candidate = nil unless cleanup == :restored
            if cleanup == :restored && verdict && !verdict[:ok] && verdict[:comparison]
              remember_comparison(edit, verdict[:comparison], :rejected)
            end
            raise "design candidate rollback or rebuild failed; inspect the transaction before retrying" if cleanup == :failed
            @say.call("#{@target[:surface].id}: candidate left untouched after a concurrent source change") if cleanup == :conflict
          end
        end
        candidate
      end

      def begin_candidate_transaction(edit)
        transaction = Transaction.new(
          root: @plan.root, paths: edit.files, id: "design-#{SecureRandom.hex(10)}"
        )
        transaction.begin!
        return transaction if candidate_current?(transaction, edit)

        transaction.release_conflicts!
        result = transaction.rollback!
        raise result.message unless result.ok?

        raise DesignEdit::Refused, "source changed before the candidate was applied"
      rescue StandardError
        transaction&.close! if transaction&.active?
        raise
      end

      def source_hashes(transaction, candidate)
        candidate.files.to_h { |file| [file, transaction.snapshot_content_hash(file)] }
      end

      def observed_hashes(transaction, candidate)
        candidate.files.to_h { |file| [file, transaction.observed_content_hash(file)] }
      end

      def candidate_current?(transaction, candidate)
        candidate.files.all? { |file| transaction.observed_current?(file) }
      end

      def apply_candidate!(transaction, candidate)
        candidate.edits.each(&:check!)
        candidate.edits.each do |edit|
          raise DesignEdit::Refused, "source changed before write" unless transaction.observed_current?(edit.file)

          original = edit.apply!
          observe_candidate_write!(transaction, edit, original)
        end
      end

      # The text read by DesignEdit#apply! must still be the transaction's
      # snapshot. Otherwise a concurrent edit arrived between snapshot and
      # proposal application; restore that exact text and leave it unclaimed.
      def observe_candidate_write!(transaction, edit, original)
        expected = transaction.snapshot_content_hash(edit.file)
        actual = Digest::SHA256.hexdigest(original)
        unless expected && expected == actual
          edit.restore(original)
          transaction.release_conflicts!
          raise DesignEdit::Refused, "source changed while the candidate was being prepared"
        end

        result = transaction.observe_paths!([edit.file])
        raise result.message unless result.ok?
        raise "candidate write could not be verified by its transaction" unless transaction.observed_current?(edit.file)
      end

      # A delivery that has a recorded commit must be reconciled, never overwritten.
      # An open or definitely-uncommitted candidate is rolled back from its snapshot.
      def restore_candidate_transaction(transaction, edit)
        return :restored unless transaction&.active?

        if transaction.state == "delivering" && transaction.delivery.pending?
          transaction.delivery.preserve!
          return :pending
        end

        conflict = !candidate_current?(transaction, edit)
        transaction.release_conflicts! if conflict
        result = transaction.rollback!
        unless result.ok?
          transaction.close!
          return :failed
        end

        rebuilt = rebuild(edit)
        return :failed unless rebuilt
        return :conflict if conflict

        :restored
      rescue StandardError => e
        transaction.close! if transaction&.active?
        @say.call("#{edit.why}: transaction cleanup failed (#{e.class})")
        :failed
      end

      # An interrupted delivery may have committed before the caller received its
      # result. Reconcile only design-owned manifests; unrelated /fix transactions
      # remain under FixLoop's lifecycle owner.
      def recover_design_transactions!
        directory = File.join(@plan.root, Transaction::ROOT_DIR)
        return unless File.directory?(directory)
        raise "design transaction directory is a symlink" if File.symlink?(directory)

        Dir.children(directory).sort.each do |id|
          next unless id.match?(/\Adesign-[a-f0-9]{20}\z/)
          next unless Transaction::Recovery.persisted?(root: @plan.root, id:)

          result = Transaction::Recovery.recover!(
            root: @plan.root, id:, release_conflicts: true
          )
          raise result.message unless result.ok?

          value = result.value!
          if value.is_a?(Array)
            rebuild_recovered_paths(value)
            next
          end
          next unless value.is_a?(Hash) && value[:state] == :delivery_pending

          transaction = Transaction::Recovery.load_persisted(root: @plan.root, id:)
          head = design_git_head
          unless head == value[:commit]
            transaction.close!
            raise "design delivery #{id} is committed at #{value[:commit]} but HEAD is #{head}; manual review required"
          end

          finalized = transaction.delivery.finalize!(head:)
          raise finalized.message unless finalized.ok?
        end
      end

      # Rollback restores SCSS/ERB source, not compiled assets. Rebuild only
      # the app bundles whose tracked source was actually restored.
      def rebuild_recovered_paths(paths)
        rails_paths = paths.map(&:to_s).select { |path| path.start_with?("RAILS/") }
        return if rails_paths.empty?
        raise "cannot rebuild recovered Rails source: build capability is unavailable" unless @world&.build

        shared = rails_paths.any? { |path| path.start_with?("RAILS/__shared/") }
        rails = File.join(@plan.root, "RAILS")
        apps = if shared
                 Dir.children(rails).select { |name| File.directory?(File.join(rails, name, "app")) }.sort
               else
                 rails_paths.filter_map do |path|
                   match = path.match(%r{\ARAILS/([^/]+)/})
                   app = match && match[1]
                   app if app && File.directory?(File.join(rails, app, "app"))
                 end.uniq.sort
               end
        apps.each do |app|
          raise "design recovery restored #{app} source but its CSS rebuild failed" unless @world.build.call(app)
        end
      end

      def design_git_head
        output, status = Master::Io::Exec.capture2e(
          "git", "-C", @plan.root, "rev-parse", "HEAD", timeout: 5
        )
        head = output.to_s.strip
        raise "design recovery could not verify Git HEAD" unless status.success? && head.match?(/\A[0-9a-f]{40}\z/)

        head
      end

      # The target plus a few others spread across the set: a stylesheet edit is
      # re-measured on a sample, not on every surface, or one round would take hours.
      def guards
        @state
      end

      # Compare eligible alternatives directly; geometry breaks only a visual tie.
      def prefer_candidate(left, right)
        verdict = JSON.parse(@world.ask.call(alternative_prompt, [left.fetch(:capture), right.fetch(:capture)])[/\{.*\}/m].to_s)
        return left if verdict["why"].to_s.strip.empty?

        case verdict["better"].to_s.upcase
        when "A" then left
        when "B" then right
        when "SAME" then left[:gain] >= right[:gain] ? left : right
        else left
        end
      rescue StandardError => e
        @say.call("alternative comparison inconclusive: #{e.class}")
        left
      end

      def judge(before, after)
        @vision = nil
        return { ok: false, text: "incomplete re-render" } unless complete_capture?(before.map { |row| row[:surface] }, after)

        now = after.find { |row| row[:surface].id == @target[:surface].id }
        return { ok: false, text: "not re-rendered" } unless now

        comparison = comparison_evidence(before).comparison_receipt(comparison_evidence(after))
        return { ok: false, text: "comparison inconclusive" } unless comparison[:status] == :observed

        gain = now[:score] - @target[:score]
        notes = problems(before, after)
        better = notes.empty? && gain >= -margin && looks_better?(now)
        { ok: better, gain:, text: summary(now, notes), comparison: }
      end

      def comparison_evidence(rows)
        shots = rows.to_h { |row| [row[:surface].id, row[:shot_sha256]] }
        measurements = rows.to_h { |row| [row[:surface].id, row[:score]] }
        Master::Review::Council::Evidence.new(
          artifact: @target[:surface].id, domain: :design,
          observations: ["layout measurements from one design-loop experiment"],
          anchors: shots.keys.sort, measurements:, structure: { screenshots: shots },
          provenance: { probe: "layout-score", conditions: { experiment: @experiment, surfaces: shots.keys.sort },
                        artifact_sha256: Digest::SHA256.hexdigest(JSON.generate(shots.sort)) },
        )
      end

      # Mechanical acceptance is not operator taste. Learn only after a confirmed
      # delivery or a restored, measured rejection, using the existing memory.
      def remember_comparison(edit, comparison, outcome)
        receipt = comparison && comparison[:receipt]
        return unless receipt

        edit.files.each do |file|
          RepairOutcomes.new(root: @plan.root).record(file, ["RENDERED_VISUAL_REFINEMENT"],
            { outcome => 1 }, pattern: "design-loop", receipt:, lesson: @vision)
        end
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "design_loop.remember_comparison")
      end

      def summary(now, notes)
        shown = notes + [@vision].compact
        "#{@target[:score].round(1)} -> #{now[:score].round(1)}#{shown.map { |note| ", #{note}" }.join}"
      end

      def problems(before, after)
        notes = []
        others = after.reject { |row| row[:surface].id == @target[:surface].id }
        lower = lower_surfaces(before, others)
        notes << "scored lower: #{lower.join(', ')}" unless lower.empty?
        added = new_offenders(before, after)
        notes << "new check offenders: #{added.join(', ')}" unless added.empty?
        notes
      end

      def lower_surfaces(before, others)
        others.filter_map do |row|
          was = before.find { |old| old[:surface].id == row[:surface].id }
          drop = (was ? was[:score] : 0) - row[:score]
          "#{row[:surface].id} -#{drop.round(1)}" if drop > OTHERS_TOLERANCE
        end
      end

      # The layout score is geometry arithmetic and does not move for many changes a
      # person would see. When it is flat, a vision model compares the two renders; the
      # order is alternated so the answer does not follow position.
      def looks_better?(now)
        @judged += 1
        order = @judged.odd? ? [@before_shot, now[:shot]] : [now[:shot], @before_shot]
        verdict = JSON.parse(@world.ask.call(vision_prompt, order)[/\{.*\}/m].to_s)
        preferred = verdict["better"].to_s.upcase
        candidate = order.first == now[:shot] ? "A" : "B"
        relation = preferred == candidate ? "candidate preferred" : preferred == "SAME" ? "no improvement" : "baseline preferred"
        @vision = "vision: #{relation}, #{verdict['why']}".strip
        !verdict["why"].to_s.strip.empty? && preferred == candidate
      rescue JSON::ParserError, StandardError
        @vision = "vision: no verdict"
        false
      end

      # A repair on one page must not hide a new offender on another page.
      def new_offenders(before, after)
        base = before.to_h { |row| [row[:surface].id, row[:offender_keys]] }
        after.flat_map do |row|
          id = row[:surface].id
          prior = base.fetch(id, {})
          row[:offender_keys].filter_map do |name, keys|
            added = Array(keys) - Array(prior[name])
            "#{id}:#{name} +#{added.size}" unless added.empty?
          end
        end
      end

      def keep(number, best)
        edit = best[:edit]
        transaction = nil
        after = @target[:score] + best[:gain]
        begin
          transaction = begin_candidate_transaction(edit)
          unless source_hashes(transaction, edit) == best[:source_hash]
            cleanup = restore_candidate_transaction(transaction, edit)
            @say.call("#{edit.why}: source changed after measurement; cleanup=#{cleanup}")
            return round(number:, why: edit.why, outcome: :failed, after: @target[:score])
          end
          apply_candidate!(transaction, edit)
          unless observed_hashes(transaction, edit) == best[:candidate_hash]
            cleanup = restore_candidate_transaction(transaction, edit)
            @say.call("#{edit.why}: candidate bytes changed after measurement; cleanup=#{cleanup}")
            return round(number:, why: edit.why, outcome: :failed, after: @target[:score])
          end
          unless rebuild(edit)
            @rejected << edit.key
            cleanup = restore_candidate_transaction(transaction, edit)
            outcome = cleanup == :restored ? :failed : :delivery_failed
            @say.call("#{edit.why}: CSS rebuild failed; candidate cleanup=#{cleanup}")
            return round(number:, why: edit.why, outcome:, after: @target[:score])
          end

          unless candidate_current?(transaction, edit)
            cleanup = restore_candidate_transaction(transaction, edit)
            @say.call("#{edit.why}: source changed before delivery; candidate cleanup=#{cleanup}")
            return round(number:, why: edit.why, outcome: :failed, after: @target[:score])
          end

          verified = measured(@fresh.map { |row| row[:surface] })
          verification = judge(@fresh, verified)
          unless verification[:ok]
            @rejected << edit.key
            @undone << "#{edit.why} (final verification: #{verification[:text]})"
            cleanup = restore_candidate_transaction(transaction, edit)
            @say.call("#{edit.why}: final verification refused the commit; cleanup=#{cleanup}")
            outcome = cleanup == :restored ? :failed : :delivery_failed
            return round(number:, why: edit.why, outcome:, after: @target[:score])
          end
          after = @target[:score] + verification[:gain]

          committed = @world.commit_file.call(edit.files.size == 1 ? edit.files.first : edit.files, commit_message(edit, after), transaction)
          unless committed && transaction.state == "committed" && !transaction.active?
            @rejected << edit.key
            @undone << "#{edit.why} (commit refused or missing transaction receipt)"
            if transaction.state == "delivering" && transaction.delivery.pending?
              transaction.delivery.preserve! if transaction.active?
              cleanup = :pending
            else
              cleanup = restore_candidate_transaction(transaction, edit)
            end
            @say.call("#{edit.why}: commit did not produce a terminal transaction receipt; cleanup=#{cleanup}")
            outcome = cleanup == :failed || cleanup == :pending ? :delivery_failed : :failed
            return round(number:, why: edit.why, outcome:, after: @target[:score])
          end

          remember_comparison(edit, verification[:comparison], :applied)
          merge(verified)
          round(number:, why: edit.why, outcome: :kept, after:)
        rescue StandardError => e
          if transaction&.state == "delivering"
            transaction.delivery.preserve! if transaction.active?
            @say.call("#{edit.why}: delivery outcome unknown (#{e.class}); transaction retained for recovery")
            round(number:, why: edit.why, outcome: :delivery_failed, after:)
          else
            cleanup = restore_candidate_transaction(transaction, edit)
            @say.call("#{edit.why}: candidate delivery failed (#{e.class}); cleanup=#{cleanup}")
            outcome = cleanup == :restored ? :failed : :delivery_failed
            round(number:, why: edit.why, outcome:, after: @target[:score])
          end
        ensure
          if transaction&.active?
            cleanup = restore_candidate_transaction(transaction, edit)
            @say.call("#{edit.why}: transaction retained after cleanup=#{cleanup}") unless cleanup == :restored
          end
        end
      end

      # MASTER's commit shape (data/commit_format.yml), which the commit-msg hook
      # enforces: a short subject naming the surface, the reasoning in the body, a
      # trailer. It was "design: <the whole rationale>." with no trailer, so the
      # hook refused every kept edit and they sat uncommitted in the tree.
      def commit_message(edit, after)
        app, page, viewport = @target[:surface].id.split("/")
        subject = "Refine the #{app} #{page.to_s.tr('_', ' ')} layout at #{viewport} width"
        body = "#{edit.why}\n\n#{@target[:surface].id} layout score #{@target[:score].round(1)} -> " \
               "#{after.round(1)}. Made by the operator-run design loop; local until the operator " \
               "pushes, and reverting this commit undoes it."
        "#{subject}\n\n#{body}\n\n#{Master::Core::World::COMMIT_TRAILER}"
      end

      # The rows re-measured after a kept edit replace their old entries; the rest stay.
      def merge(fresh)
        ids = fresh.to_h { |row| [row[:surface].id, row] }
        @state = @state.map { |row| ids.fetch(row[:surface].id, row) }
      end

      def round(number:, why:, outcome:, after:)
        Round.new(number:, surface: @target[:surface].id, why:, outcome:, before: @target[:score], after:)
      end

    end
  end
end
