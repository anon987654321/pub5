# frozen_string_literal: true

require "date"
require_relative "scan"
require_relative "preflight"
require_relative "repair"
require_relative "autofix"
require_relative "leases"

module Fix
  # One /fix run over one scope: reap what a dead run left serving, take the
  # tree's lock, preflight the paths, scan (incremental), publish the census
  # for bulk Laws, deliver the deterministic rewrites, repair file by file
  # until the findings, the budget or the stall guard run out, rescan for the
  # ratchet, and report what landed, what was refused and what it cost.
  class Run
    RUN_BUDGET_S = 3 * 3600
    STALL_S = 600
    CENSUS_DIR = "tmp/fix/census"
    BULK_FILES = 20
    MAX_PASSES = 3

    attr_reader :stopping, :tracked

    def initialize(world:, scope:, laws:, model:, writer:, focus: nil, dry_run: false, visual: nil, out: $stdout,
                   tests: nil, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
      @world = world
      @scope = scope
      @all_laws = laws
      @focus = focus
      @dry_run = dry_run
      @visual = visual
      @model = model
      @writer = writer
      @out = out
      @tests = tests
      @clock = clock
      @refused = []
      @refusals = Core::Ledger.new(File.join(world.manifest.root, "log", "fix_refusals.jsonl"))
    end

    def say(line) = @out.puts("fix0: #{line}")

    # The stall guard reads this: anything that advances the run calls it.
    def pulse(note = nil)
      @last_progress = @clock.call
      say(note) if note
    end

    def seconds_left = @deadline && (@deadline - @clock.call)

    def stop!(reason) = @stopping ||= reason

    def call
      started = @clock.call
      @deadline = started + RUN_BUDGET_S
      pulse
      reaped = ServerLeases.reap_orphans!(@world)
      say("stopped #{reaped.join(', ')}, left serving by a dead run") if reaped.any?
      lock = Preflight.lock!(@world, @scope)
      begin
        execute(started)
      ensure
        Preflight.release(@world, lock)
      end
    end

    private

    def execute(started)
      laws = Scan.scanning(@all_laws, focus: @focus)
      @tracked = TreeDigest.files(@world, "--cached", "--others", "--exclude-standard", ".")
      scan = Scan.new(world: @world, laws:, scope: @scope)
      opening = scan.call
      say("scan #{@scope}: #{laws.size} Laws over #{opening.files} files, #{opening.scanned} rescanned, " \
          "#{opening.findings.size} findings in #{opening.seconds}s#{' (tree unchanged)' if opening.cached_tree}")
      plan = plan(opening.findings, laws)
      return dry_run(plan) if @dry_run
      return 1 unless preflight(plan[:repair].keys)

      writes = Autofix.run(@world, plan[:repair].values.flatten, laws:)
      deliver(writes)
      watch = watch_stall
      tally = passes(plan, laws, scan)
      watch.kill
      visual = @visual&.call(self)
      closing = scan.call
      report(started, opening, closing, tally, visual)
    end

    # Which findings this run repairs, and which it holds and why.
    def plan(findings, laws)
      by_law = laws.to_h { |law| [law.id, law] }
      held = Hash.new { |h, k| h[k] = [] }
      repairable = findings.select do |finding|
        law = by_law[finding.law]
        reason = hold_reason(law, findings)
        held[reason] << finding if reason
        law && reason.nil?
      end
      repairable = repairable.reject do |finding|
        old = predates?(finding, by_law[finding.law])
        held["predates enactment"] << finding if old
        old
      end
      { repair: repairable.group_by(&:file), held: }
    end

    def hold_reason(law, findings)
      return "unknown Law" unless law
      return "autofix never" if law.policy.fetch("autofix", "never") == "never"

      files = findings.select { |f| f.law == law.id }.map(&:file).uniq.size
      "bulk: #{files} files, census unpublished" if files > BULK_FILES && !census_published?(law.id)
    end

    def census_published?(id) = (@world.read(census_path(id)).size.positive? rescue false)

    def census_path(id) = File.join(CENSUS_DIR, "#{id}.txt")

    # Laws never rewrite text written before they were enacted (PLAN.md
    # section 5). One blame a file, read once a run; a line not yet
    # committed is new.
    def predates?(finding, law)
      enacted = law&.policy&.fetch("enacted", nil) or return false
      time = line_times(finding.file)[finding.line] or return false
      Time.at(time).utc.to_date < Date.parse(enacted.to_s)
    rescue Date::Error
      false
    end

    def line_times(file)
      (@blame ||= {})[file] ||= begin
        times = {}
        sha = nil
        commits = {}
        @world.git("blame", "--porcelain", "--", file).out.each_line do |line|
          if (head = line.match(/\A(\h{40}) \d+ (\d+)/))
            sha = head[1]
            times[head[2].to_i] = sha
          elsif (stamp = line[/\Aauthor-time (\d+)/, 1])
            commits[sha] = stamp.to_i
          end
        end
        times.to_h { |n, commit| [n, commit.match?(/\A0+\z/) ? nil : commits[commit]] }.compact
      end
    end

    def dry_run(plan)
      plan[:repair].each { |file, rows| say("would repair #{file}: #{rows.map(&:law).uniq.join(', ')}") }
      plan[:held].each { |reason, rows| say("held #{rows.size} (#{reason})") }
      publish_census(plan)
      say("dry run: #{plan[:repair].size} files would be repaired; nothing written outside tmp/fix")
      0
    end

    # A Law whose autofix would reach more than BULK_FILES files publishes
    # its census first (PLAN.md section 5, the ASCII_PUNCTUATION lesson).
    def publish_census(plan)
      plan[:held].select { |reason, _| reason.start_with?("bulk") }.each_value do |rows|
        rows.group_by(&:law).each do |id, found|
          lines = found.map { |f| "#{f.file}:#{f.line}: #{f.message || f.text.strip}" }
          @world.write(census_path(id), "#{id}: #{found.size} findings in #{found.map(&:file).uniq.size} files\n#{lines.join("\n")}\n")
          say("census #{id} published at #{census_path(id)}")
        end
      end
    end

    def preflight(paths)
      report = Preflight.check(@world, paths)
      say("preflight: #{report.drifting.size} file(s) moved under another writer; going on") if report.drifting.any?
      report.broken.each { |path, problem| say("preflight: #{path}: #{problem}") }
      report.broken.empty?
    end

    def deliver(writes)
      return unless writes.any?

      ours, left = writes.split(@world)
      left.each { |row| say("left #{row.path}: changed since the autofix wrote it") }
      return if ours.empty?

      paths = ours.map(&:path)
      message = CommitMessage.autofix(paths:, laws: ours.flat_map(&:laws).uniq, writer: @writer)
      @world.git("add", "--", *paths)
      run = @world.git("commit", "-q", "-m", message, "--", *paths)
      return say("delivered #{paths.size} deterministic rewrite(s)") if run.ok?

      ours.each { |row| @world.write(row.path, row.before) if @world.read(row.path).b == row.after }
      @world.git("reset", "-q", "--", *paths)
      say("the autofix commit was refused; put back #{paths.size} file(s)")
    end

    # The stall guard (pub4 ad91bab976): no progress for STALL_S stops the
    # run, and the loop reads the stop before each next file.
    def watch_stall
      Thread.new do
        loop do
          sleep 5
          stop!("stalled, no progress for #{STALL_S}s") if @clock.call - @last_progress > STALL_S
          stop!("run budget #{RUN_BUDGET_S}s spent") if seconds_left.to_i <= 0
        end
      end
    end

    # Up to MAX_PASSES passes; a pass rescans the files the last one
    # repaired, and a file refused once this run is not asked again.
    def passes(plan, laws, scan)
      repair = Repair.new(run: self, world: @world, model: @model, laws:, refusals: @refusals, writer: @writer,
                          tests: @tests)
      tally = []
      MAX_PASSES.times do |index|
        done = repair_pass(repair, plan[:repair].reject { |file, _| @refused.include?(file) })
        tally.concat(done)
        break if @stopping || done.none? { |o, _| o.status == :landed } || index == MAX_PASSES - 1

        plan = plan(scan.call.findings, laws)
      end
      tally
    end

    def repair_pass(repair, groups)
      out = []
      groups.sort_by { |file, rows| [-rows.size, file] }.each do |file, rows|
        if @stopping
          say("stopping (#{@stopping}); #{groups.size - out.size} file(s) wait for the next run")
          break
        end
        spent = spend
        outcome = repair.call(file, rows)
        @refused << file unless outcome.status == :landed
        pulse("#{outcome.status} #{file}#{" (#{outcome.reason})" if outcome.reason}")
        out << [outcome, spend_since(spent)]
      end
      out
    end

    def spend = @world.ledger.spend

    def spend_since(before)
      now = spend
      %w[tokens_in tokens_out cost_usd unpriced_calls].to_h { |k| [k, (now[k] - before[k]).round(6)] }
    end

    def report(started, opening, closing, tally, visual)
      outcomes = tally.map(&:first)
      landed = tally.select { |o, _| o.status == :landed }
      refused = tally.reject { |o, _| o.status == :landed }
      say("landed #{landed.size}, refused #{refused.size}: " \
          "#{refused.map { |o, _| o.status }.tally.map { |k, v| "#{k} #{v}" }.join(', ')}") unless outcomes.empty?
      [["landed", landed], ["refused", refused]].each do |name, rows|
        next if rows.empty?

        tokens = rows.sum { |_, s| s["tokens_in"] + s["tokens_out"] }
        say("tokens per #{name} repair #{(tokens.to_f / rows.size).round}, cost #{rows.sum { |_, s| s['cost_usd'] }.round(4)} USD")
      end
      risen = ratchet(opening, closing)
      risen.each { |id, (was, now)| say("ratchet: #{id} rose #{was} -> #{now}") }
      say("visual: #{visual}") if visual
      say("closing scan #{closing.seconds}s; stopped: #{@stopping}") if @stopping
      say("done in #{(@clock.call - started).round}s")
      risen.empty? ? 0 : 1
    end

    # A Law's count over the scope may not rise between the opening and the closing scan.
    def ratchet(opening, closing)
      was = opening.findings.map(&:law).tally
      closing.findings.map(&:law).tally.filter_map { |id, now| [id, [was.fetch(id, 0), now]] if now > was.fetch(id, 0) }.to_h
    end
  end
end
