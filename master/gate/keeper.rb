# frozen_string_literal: true

require "json"
require_relative "repo"
require_relative "writers"

module Gatekeeper
  # One gate run over origin: judge each new first-parent commit on main by
  # running its own bin/check in a clean worktree, record what an unbranch-
  # protected repository cannot block (an inbox-tier writer on main, a
  # rewritten main), then merge each inbox/<writer> branch whose merge onto
  # main passes bin/check and stays inside the writer's trees. Every verdict
  # and decision is one `gate` line in the ledger; a SHA is judged once and
  # an inbox tip decided once, so a second run over the same origin is a no-op.
  class Keeper
    REMOTE = "origin"
    BRANCH = "main"
    WORK = "tmp/gate"
    MARKER = "log/gate/FAILED"
    OK_LINE = {
      "parse" => /\Aparse: \d+ files, 0 broken\z/,
      "laws" => /\Alaws: \d+ loaded.* 0 enforced findings/,
      "test" => /\Atest: \d+ runs, \d+ assertions, 0 failures, 0 errors/
    }.freeze

    attr_reader :tally

    def initialize(world:, out:, knobs: Core::Knobs.default, writers: Writers.new,
                   protected_paths: Core::Registry.load(:paths).fetch("protected"))
      @world = world
      @out = out
      @repo = Repo.new(world)
      @writers = writers
      @protected = protected_paths
      @knobs = knobs
      @tally = Hash.new(0)
    end

    def history = @history ||= @world.ledger.entries.select { |e| e["kind"] == "gate" }

    def call
      @repo.out!("fetch", "--prune", "--quiet", REMOTE, timeout: Repo::NETWORK_TIMEOUT)
      clean_worktrees
      @main = @repo.out!("rev-parse", "--verify", "#{REMOTE}/#{BRANCH}^{commit}")
      verdicts = judge_main
      revert(verdicts) if @knobs.fetch("PUB5_GATE_AUTO_REVERT")
      inbox
      summary
    end

    private

    def record(event, **fields)
      entry = @world.ledger.append(:gate, event:, **fields)
      history << entry
      entry
    end

    def say(line) = @out.puts("gate: #{line}")

    def short(sha) = sha.to_s[0, 10]

    def verdicts = history.select { |e| e["event"] == "verdict" }

    # --- main ---------------------------------------------------------------

    def judge_main
      last = last_tip
      shas = new_commits(last)
      shas.map { |sha| judge_pushed(sha) }.tap { |judged| mark(judged) }
    end

    # The main tip the gate last saw: its last verdict on main, or the new tip
    # of a rewrite it recorded, so one rewrite is one violation, not one a run.
    def last_tip
      entry = history.reverse.find do |e|
        (e["event"] == "verdict" && e["ref"] == BRANCH) || (e["event"] == "violation" && e["reason"] == "force-push")
      end
      entry && (entry["new"] || entry["sha"])
    end

    # First-parent commits only: what reached main through a gate merge was
    # judged as that merge. With no verdict yet, only the tip is judged: the
    # gate starts from now, not from the first commit. A main that no longer
    # descends from the last judged SHA was rewritten: that is recorded, and
    # judging restarts at the new tip.
    def new_commits(last)
      judged = verdicts.to_h { |e| [e["sha"], true] }
      return judged.include?(@main) ? [] : [@main] if last.nil?
      return [] if last == @main

      unless @repo.commit?(last) && @repo.ancestor?(last, @main)
        violation(sha: @main, writer: nil, author: nil, reason: "force-push", old: last, new: @main,
                  line: "main rewritten: #{short(last)} is not an ancestor of #{short(@main)}")
        return judged.include?(@main) ? [] : [@main]
      end

      @repo.out!("rev-list", "--first-parent", "--reverse", @main, "^#{last}").split.reject { |s| judged.include?(s) }
    end

    def judge_pushed(sha)
      commit = @repo.commit(sha)
      writer = @writers.writer(commit)
      verdict = judge(sha, commit:, writer:)
      if @writers.tier(commit) == "inbox"
        reason = @writers.inbox_author?(commit) ? "pushed to main as #{commit['author']} (inbox tier)" : "pushed to main (inbox tier)"
        violation(sha:, writer:, author: commit["author"], reason:, line: "violation #{short(sha)} #{writer} #{reason}")
      end
      verdict
    end

    def violation(line:, **fields)
      record("violation", **fields)
      @tally[:violations] += 1
      say(line)
    end

    def judge(sha, commit:, writer:, ref: BRANCH)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      step, detail, output = check(sha)
      seconds = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(1)
      result = step ? "FAIL" : "PASS"
      @world.write("log/gate/#{short(sha)}.out", output) if step
      entry = record("verdict", ref:, sha:, result:, step:, detail:, author: commit["author"], writer:,
                                subject: commit["subject"], parent: commit["parents"].first, seconds:)
      @tally[result == "PASS" ? :passed : :failed] += 1 if ref == BRANCH
      say("#{short(sha)} #{result} #{writer} #{commit['author']}#{" #{step}: #{detail}" if step} #{seconds}s")
      entry
    end

    # [step, detail, output]; step is nil when bin/check passed. The commit
    # is judged by its own bin/check in a worktree of its own: the gate's
    # checkout never moves.
    def check(sha)
      path = File.join(@repo.root, WORK, short(sha))
      remove_worktree(path)
      added = @repo.run("worktree", "add", "--detach", "--force", "--quiet", path, sha)
      return ["worktree", added.err.strip.lines.first.to_s.strip, added.err] unless added.ok?
      return ["check", "no bin/check in this commit", ""] unless File.file?(File.join(path, "bin/check"))

      run = @world.exec(RbConfig.ruby, "bin/check", chdir: path, timeout: @knobs.fetch("PUB5_GATE_CHECK_TIMEOUT"),
                                                     unset: Repo::INHERITED + ["PUB5_LEDGER"])
      output = run.out + run.err
      return [nil, nil, output] if run.ok?
      return ["timeout", "bin/check ran past #{@knobs.fetch('PUB5_GATE_CHECK_TIMEOUT')}s", output] if run.timed_out

      [*failing_step(output), output]
    ensure
      remove_worktree(path) if path
    end

    # bin/check prints one line per stage, in order; the first stage line
    # that is not its passing summary names the step.
    def failing_step(output)
      output.each_line(chomp: true) do |line|
        stage = line[/\A(parse|laws?|test):/, 1]
        stage = "laws" if stage == "law"
        return [stage, line.sub(/\A\w+:\s*/, "")[0, 240]] if stage && !line.match?(OK_LINE.fetch(stage))
      end
      ["check", output.lines.map(&:strip).reject(&:empty?).last.to_s[0, 240]]
    end

    def remove_worktree(path)
      @repo.run("worktree", "remove", "--force", path) if File.exist?(path)
    end

    def clean_worktrees
      @repo.run("worktree", "prune")
      work = File.join(@repo.root, WORK)
      @repo.out!("worktree", "list", "--porcelain").each_line do |line|
        path = line.delete_prefix("worktree ").strip
        remove_worktree(path) if line.start_with?("worktree ") && path.start_with?("#{work}/")
      end
    end

    # The marker exists while main is red: it names the failing commit and
    # goes when a later commit on main passes.
    def mark(judged)
      return if judged.empty?

      tip = judged.last
      if tip["result"] == "FAIL"
        first = judged.find { |v| v["result"] == "FAIL" }
        @world.write(MARKER, "#{first['sha']} #{first['writer']} #{first['author']} #{first['step']}: #{first['detail']}\n" \
                             "tip #{tip['sha']} FAIL #{tip['step']}\n")
      else
        @world.exec("rm", "-f", MARKER, chdir: @repo.root)
      end
    end

    # --- auto-revert (PUB5_GATE_AUTO_REVERT, off by default) ----------------

    # Only a commit that broke a green main is reverted: its parent passed.
    # A commit that is red because its parent is red is not the cause.
    def revert(judged)
      judged.select { |v| v["result"] == "FAIL" }.each do |v|
        parent = verdicts.reverse.find { |e| e["sha"] == v["parent"] }
        reason = if @repo.commit(v["sha"])["parents"].size != 1 then "a merge commit"
                 elsif parent.nil? || parent["result"] != "PASS" then "its parent was not judged green"
                 end
        next skip_revert(v, reason) if reason

        tree = @repo.run("merge-tree", "--write-tree", "--merge-base=#{v['sha']}", @main, v["parent"])
        next skip_revert(v, "the revert conflicts with main") unless tree.ok?

        message = ["Revert #{short(v['sha'])} after it failed the gate",
                   "This reverts commit #{v['sha']} (#{v['subject']}) by #{v['author']}, writer #{v['writer']}: " \
                   "bin/check failed at #{v['step']}: #{v['detail']}",
                   "Gate: reverted #{v['sha']}"]
        sha = @repo.out!("commit-tree", tree.out.lines.first.strip, "-p", @main, *message.flat_map { |m| ["-m", m] })
        next skip_revert(v, "main moved; retried next run") unless push(sha)

        @main = sha
        record("revert", sha: v["sha"], decision: "reverted", revert: sha)
        @tally[:reverted] += 1
        say("reverted #{short(v['sha'])} by #{short(sha)}")
      end
    end

    def skip_revert(verdict, reason)
      record("revert", sha: verdict["sha"], decision: "skipped", reason:)
      say("not reverted #{short(verdict['sha'])}: #{reason}")
    end

    # Never forced: a main that moved since the fetch rejects the push.
    def push(sha) = @repo.run("push", "--quiet", REMOTE, "#{sha}:refs/heads/#{BRANCH}", timeout: Repo::NETWORK_TIMEOUT).ok?

    # --- inbox --------------------------------------------------------------

    def inbox
      @repo.out!("for-each-ref", "--format=%(refname:strip=3)", "refs/remotes/#{REMOTE}/inbox/").split.each do |branch|
        tip = @repo.out!("rev-parse", "#{REMOTE}/#{branch}^{commit}")
        next if decided?(branch, tip) || @repo.ancestor?(tip, @main)

        writer = @writers.for_branch(branch)
        reason = refusal(branch, writer, tip)
        reason ? leave(branch, tip, writer, reason) : merge(branch, tip, writer)
      end
    end

    def decided?(branch, tip)
      history.any? { |e| e["event"] == "inbox" && e["branch"] == branch && e["tip"] == tip && e["decision"] != "retry" }
    end

    def refusal(branch, writer, tip)
      return "#{branch} belongs to no writer in registry/writers.yml" unless writer

      paths = @repo.out!("diff", "--name-only", "-z", "#{@main}...#{tip}").split("\0")
      return "changes nothing against main" if paths.empty?

      outside = paths.reject { |p| @writers.inside?(writer, p) }
      return "outside #{writer}'s trees: #{outside.first(5).join(', ')}" if outside.any?

      guarded = paths.select { |p| @protected.any? { |glob| Core::Manifest.match?(glob, p) } }
      "protected by registry/paths.yml: #{guarded.first(5).join(', ')}" if guarded.any?
    end

    def merge(branch, tip, writer)
      tree = @repo.run("merge-tree", "--write-tree", @main, tip)
      return leave(branch, tip, writer, "conflicts with main") unless tree.ok?

      message = ["Merge #{branch} at #{short(tip)}",
                 "The gate merged #{branch} (tip #{tip}) after bin/check passed on the merge with main #{short(@main)}; " \
                 "every changed path is inside #{writer}'s trees.",
                 "Gate: merged #{branch} #{tip}"]
      sha = @repo.out!("commit-tree", tree.out.lines.first.strip, "-p", @main, "-p", tip, *message.flat_map { |m| ["-m", m] })
      verdict = judge(sha, commit: @repo.commit(sha), writer: Writers::GATE, ref: branch)
      return leave(branch, tip, writer, "bin/check failed on the merge at #{verdict['step']}: #{verdict['detail']}") if verdict["step"]
      return leave(branch, tip, writer, "main moved during the merge; retried next run", decision: "retry") unless push(sha)

      record("verdict", **verdict.slice("sha", "result", "author", "writer", "subject", "parent", "seconds").transform_keys(&:to_sym),
                        ref: BRANCH, step: nil, detail: "judged as the merge of #{branch}")
      @main = sha
      record("inbox", branch:, tip:, writer:, decision: "merged", merge: sha)
      @tally[:merged] += 1
      say("#{branch} #{short(tip)} merged as #{short(sha)}")
    end

    def leave(branch, tip, writer, reason, decision: "left")
      record("inbox", branch:, tip:, writer:, decision:, reason:)
      @tally[:left] += 1
      say("#{branch} #{short(tip)} left: #{reason}")
    end

    def summary
      t = @tally
      say("nothing new; main #{short(@main)}") if t.empty?
      say("#{t[:passed] + t[:failed]} judged (#{t[:failed]} failed), #{t[:merged]} merged, #{t[:left]} left, " \
          "#{t[:violations]} violations#{", #{t[:reverted]} reverted" if t[:reverted].positive?}") unless t.empty?
      t[:failed].positive? || t[:violations].positive? ? 1 : 0
    end
  end
end
