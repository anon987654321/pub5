# frozen_string_literal: true

module Master
  module Fix
    module Scan
      # The model tier of the scan, re-opening the FileProcessor defined in
      # fix/scan/file_processor.rb: the schedule a /fix pass uses to turn the
      # tier off, defer, budget and replay its reads, and the outage evidence a
      # model tier that could not answer leaves behind. Reading files and
      # running the law passes stay in the defining file; every path here is
      # listed in data/autoload.yml under autoload.reopens_a_constant_defined_elsewhere.
      class FileProcessor
        def skip_semantic!
          @skip_semantic = true
        end

        def full_semantic!
          @skip_semantic = false
          @semantic_sample_override = 1.0
        end

        def semantic_full? = @semantic_sample_override.to_f >= 1.0

        # Within the block, on this thread, a due model read with no replayable answer is listed in
        # +into+ instead of made, so the cheap findings of a whole corpus reach repair first and the
        # caller reads the list afterwards under a budget (FixLoop::PassRunner::StreamStage). Read
        # inline at a minute and a half a file, twenty files hold the first repair for half an hour.
        # Other threads, a repair verifying its own edit among them, still read inline.
        def deferring_semantic(into, &) = scoped(:@deferral, into, &)

        # Within the block, on this thread, a model read is made only while +budget+ is open, and its
        # wall time is charged to it.
        def budgeting_semantic(budget, &) = scoped(:@semantic_budget, budget, &)

        # Semantic outages are explicit evidence, separate from files that failed
        # mechanical measurement. They prevent DONE without hiding deterministic
        # findings from the same file.
        def semantic_gaps
          @semantic_gap_mutex.synchronize { @semantic_gaps.dup }
        end

        def reset_semantic_gaps!
          @semantic_gap_mutex.synchronize do
            @semantic_gaps.clear
            @semantic_gap_notice_emitted = false
            @unmodelled_notice_emitted = false
          end
          self
        end

        # The model tier off for the length of one block, then back as it was.
        # A tree-wide observation is a mechanical reading: 75% of RAILS files
        # carry a finding, so "run the model when the cheap passes found
        # something" put about 5,000 model calls of 50 to 190 seconds each
        # inside one walk. The operator asking for every file to be read
        # (MASTER_SCAN_SEMANTIC_SAMPLE=1, or a mode at 1.0) still wins. A
        # requested /fix's own full_semantic! does not: it is set on the shared
        # scanner for the repair's budgeted passes, and leaking into the
        # re-observe it sent all 2,049 MASTER files to the model inline.
        def mechanical_only
          previous = @skip_semantic
          @skip_semantic = true unless Master::Ground::ModePosture.semantic_sample >= 1.0
          yield
        ensure
          @skip_semantic = previous
        end

        private

        # Constructor state of the model tier, kept beside the methods that read it.
        def init_semantic_tier_state(skip_semantic:, cache_root:)
          @skip_semantic = skip_semantic
          @semantic_gap_mutex = Mutex.new
          @semantic_gaps = {}
          @semantic_gap_notice_emitted = false
          @semantic_reads = FindingCache.new(root: cache_root, dir: SEMANTIC_DIR)
          @deferral = nil
          @semantic_budget = nil
        end

        # A replay costs nothing and is always taken; a fresh read waits while the pass defers, and is
        # refused once the pass's budget is spent.
        def semantic_findings(found, reading)
          return skipped(reading, OUTSIDE_SAMPLE) unless semantic_due?(found, reading.path)
          return [] if (reading = modelled(reading)).laws.empty?

          replayed = @semantic_reads.replay(reading.subject(relative_progress_path(reading.path)))
          return skipped(reading, UNCHANGED) + replayed unless replayed.nil?
          return defer(reading) if on_this_thread(@deferral)
          return skipped(reading, OVER_BUDGET) unless semantic_budget_open?

          budgeted_read(reading)
        end

        def skipped(reading, reason)
          note_skip(path: reading.path, laws: reading.laws, reason:)
          []
        end

        def defer(reading)
          into = on_this_thread(@deferral)
          @semantic_gap_mutex.synchronize { into << reading.path }
          skipped(reading, DEFERRED)
        end

        def semantic_budget_open?
          budget = on_this_thread(@semantic_budget)
          budget.nil? || budget.open?
        end

        def budgeted_read(reading)
          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          read_semantic(**reading.to_h)
        ensure
          on_this_thread(@semantic_budget)&.charge(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)
        end

        def scoped(ivar, value)
          previous = instance_variable_get(ivar)
          instance_variable_set(ivar, [Thread.current, value])
          yield
        ensure
          instance_variable_set(ivar, previous)
        end

        def on_this_thread(pair) = pair&.first == Thread.current ? pair.last : nil

        # Fraction of otherwise-clean files that still get the semantic pass, from
        # Ground::ModePosture. Keyed on the path digest rather than rand, so two scans
        # of the same tree ask the same questions and their reports can be compared.
        def semantic_sample
          return @semantic_sample_override if @semantic_sample_override

          Master::Ground::ModePosture.semantic_sample
        end

        # Relative to the repo, not the absolute path: keyed on the latter, two
        # checkouts of the same tree sample different files and a scan is not
        # reproducible off the machine that ran it. Relative also holds still
        # while the file is edited, so a law does not switch on and off under
        # someone's keystrokes.
        def sample_key(path)
          path.to_s.delete_prefix("#{Master::ROOT}/")
        end

        # A read is kept, clean or not, only when every semantic law answered: an inconclusive read leaves a
        # gap and is asked again. Asking about unchanged text again re-rolls the answer and buys nothing,
        # at 50 to 190 seconds a call; the next edit to the file, its laws or the scanner asks afresh.
        def read_semantic(path:, code:, ast:, laws:)
          semantic = run_law_pass(pass: :semantic, laws:, code:, ast:, path:)
          relative = relative_progress_path(path)
          answered = !@semantic_gap_mutex.synchronize { @semantic_gaps.key?(relative) }
          return semantic unless answered && !relative.start_with?("/")

          @semantic_reads.record(FindingCache::Subject.new(relative, code, laws, ast), semantic)
          semantic
        end

        def note_skip(path:, laws:, reason:)
          @bus&.publish("scan:semantic_skipped", path:, law_count: laws.size, reason:)
        end

        # 74 of the 225 declared rules reach a file only through the semantic
        # pass, and the pass ran only when the cheap passes had already found
        # something. So a file that read as clean was never asked the 74
        # questions — and reported "0 findings", which is a claim about the whole
        # law set rather than about the third of it that ran.
        #
        # The cost check is real: one LLM call per file is not free on a tree this
        # size. Keeping it, but sampling a deterministic slice so clean files are
        # not permanently exempt, and saying so when a file is skipped.
        def semantic_due?(findings, path)
          return false if @skip_semantic || CheckFocus.blockers?
          return true unless findings.empty?
          return false if semantic_sample <= 0

          window = (semantic_sample * 1000).round
          bucket = Digest::SHA256.hexdigest(sample_key(path))[0, 8].to_i(16) % 1000
          (bucket - (rotation_day * window)) % 1000 < window
        end

        # Recorded where an unanswered semantic read is, so the file blocks DONE as
        # inconclusive while the rest of the walk goes on.
        def unmeasured(path, error)
          relative = relative_progress_path(path)
          @semantic_gap_mutex.synchronize { @semantic_gaps[relative] ||= "INCONCLUSIVE: #{error.message}"[0, 240] }
          @bus&.publish("scan:inconclusive", path: relative, reason: error.message)
          Master::Trace::Dmesg.status("scan0", "inconclusive, #{error.message}"[0, 200])
          Result.ok([])
        end

        def semantic_inconclusive?(error)
          error.is_a?(Review::Scan::Detector::SemanticAssessmentInconclusive)
        end

        def record_semantic_inconclusive(path:, law:, error:)
          relative = relative_progress_path(path)
          law_id = law.respond_to?(:id) ? law.id.to_s : law.class.name.to_s
          detail = "#{law_id}: #{error.message.to_s[0, 220]}"
          first_file, announce = @semantic_gap_mutex.synchronize do
            next [false, false] if @semantic_gaps.key?(relative)

            @semantic_gaps[relative] = detail
            first_notice = !@semantic_gap_notice_emitted
            @semantic_gap_notice_emitted = true
            [true, first_notice]
          end
          return unless first_file

          @bus&.publish("scan:semantic_inconclusive", path: relative, law: law_id, message: detail)
          Master::Trace::Dmesg.status("law0", "semantic assessment inconclusive; details recorded for #{relative}"[0, 200]) if announce
        end
      end
    end
  end
end
