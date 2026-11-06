# frozen_string_literal: true

require "timeout"
require_relative "scope"
require_relative "../models/dispatch"
require_relative "transaction"
require_relative "commit_message"

module Fix
  # Candidates are independent asks against the same unchanged source, so
  # they run concurrently (pub4 f52307b568). A thread starts with no
  # thread-locals and the repair keeps its retry note there, so each thread
  # starts with its parent's (Ruby's own __ keys excepted); a candidate still
  # running when the caller gives up (the file budget) is killed rather than
  # left holding a model call.
  module Candidates
    module_function

    def collect(count, &block)
      locals = Thread.current.keys.reject { |key| key.to_s.start_with?("__") }.to_h { |key| [key, Thread.current[key]] }
      threads = Array.new(count) do |index|
        Thread.new do
          locals.each { |key, value| Thread.current[key] = value }
          block.call(index)
        end
      end
      threads.map(&:value)
    ensure
      threads&.each { |thread| thread.kill if thread.alive? }
    end
  end

  # One proposal for one file, asked through master/models' Dispatch (the
  # one door: routing, the cool-off and load gate, the lane breaker and the
  # ledger live there): the fullest scope window of its findings,
  # asked of the model, judged in memory (parse, rescan, scope, guards), then
  # written, tested and committed inside a Transaction. Every outcome is a
  # symbol the run tallies; a refusal names its stage.
  class Repair
    CANDIDATES = 2
    FILE_BUDGET_S = 240
    RETRY_NOTE = :fix_retry_note
    Outcome = Data.define(:status, :path, :reason, :laws)

    def initialize(run:, world:, model:, laws:, refusals:, writer:, tests: nil)
      @run = run
      @world = world
      @model = model
      @laws = laws
      @refusals = refusals
      @writer = writer
      @tests = tests || method(:mapped_tests)
    end

    def call(path, findings)
      return outcome(:skip_protected, path, "protected by registry/paths.yml", findings) if protected?(path)
      return outcome(:stopped, path, @run.stopping, findings) if @run.stopping

      taken, deferred = Scope.narrow(findings)
      @run.say("#{path}: proposing #{taken.size} finding(s), #{deferred.size} wait for the next pass") if deferred.any?
      attempt(path, taken)
    end

    private

    def protected?(path) = @world.manifest.protected?(path)

    def outcome(status, path, reason, findings) = Outcome.new(status:, path:, reason:, laws: findings.map(&:law).uniq)

    # One try and one retry that shows the model why the first was refused.
    def attempt(path, findings, note: nil)
      Thread.current[RETRY_NOTE] = note
      old = @world.read(path).force_encoding("UTF-8")
      chosen, refusal = propose(path, old, findings)
      return outcome(:no_proposal, path, refusal, findings) if chosen.nil? && refusal.nil?
      return land(path, old, chosen, findings) if chosen
      return outcome(:refused, path, refusal, findings) if note || @run.stopping

      attempt(path, findings, note: refusal)
    rescue Models::Dispatch::Exhausted => e
      outcome(:lane_down, path, e.message, findings)
    rescue Core::Refusal => e
      raise unless e.verb == :llm

      @run.stop!(e.message)
      outcome(:stopped, path, e.message, findings)
    ensure
      Thread.current[RETRY_NOTE] = nil
    end

    # [text, nil] for the best candidate that passed the in-memory gates;
    # [nil, reason] when every one was refused; [nil, nil] when none came.
    def propose(path, old, findings)
      texts = Timeout.timeout(FILE_BUDGET_S) do
        Candidates.collect(CANDIDATES) { @model.ask(prompt(path, old, findings), task: "code") }
      end.map { |answer| extract(answer.text) }.compact.uniq - [old]
      return [nil, nil] if texts.empty?

      judged = texts.map { |text| [text, judge(path, old, text, findings)] }
      best = judged.select { |_, verdict| verdict.is_a?(Integer) }.min_by { |text, count| [count, (text.size - old.size).abs] }
      best ? [best.first, nil] : [nil, judged.first.last]
    rescue Timeout::Error
      [nil, "skipped, #{FILE_BUDGET_S}s file budget spent"]
    end

    # The remaining finding count, or why the candidate is refused.
    def judge(path, old, text, findings)
      kind = Core::ParseGate.kind(path)
      problem = kind && Core::ParseGate.problem(kind, text)
      return "does not parse: #{problem}" if problem
      return "out of scope: #{Scope.outside(findings, old, text)}" if Scope.outside(findings, old, text)

      guard = Scope.dropped_guard(old, text)
      return "unsafe: #{guard}" if guard

      before = scan(old, path)
      after = scan(text, path)
      targeted = findings.map(&:law).uniq
      return "the rescan still finds #{targeted.join(', ')}" if count(after, targeted) >= count(before, targeted)
      return "the rescan finds #{after.size} findings, #{before.size} before" if after.size > before.size

      after.size
    end

    def scan(text, path) = @laws.flat_map { |law| law.scan(text, path) }

    def count(findings, laws) = findings.count { |finding| laws.include?(finding.law) }

    def land(path, old, text, findings)
      transaction = Transaction.new(world: @world, path:, refusals: @refusals)
      transaction.apply(text)
      failed = @tests.call(path).find { |test| !run_test(test) }
      if failed
        transaction.refuse(:tests, "#{failed} failed", laws: findings.map(&:law).uniq)
        return outcome(:refused, path, "test #{failed} failed; put back", findings)
      end
      commit(transaction, path, old, text, findings)
    end

    def commit(transaction, path, old, text, findings)
      laws = findings.map(&:law).uniq
      tests = @tests.call(path)
      message = CommitMessage.repair(laws:, file: path, line: findings.map(&:line).min, before: scan(old, path).size,
                                     after: scan(text, path).size, writer: @writer,
                                     proof: tests.empty? ? "parse gate and rescan; no mapped test" : tests.join(", "))
      @world.git("add", "--", path)
      run = @world.git("commit", "-q", "-m", message, "--", path)
      return outcome(:landed, path, nil, findings) if run.ok?

      put = transaction.refuse(:commit, run.err.strip.lines.last(3).join(" "), laws:)
      outcome(:commit_refused, path, "the commit was refused; #{put}", findings)
    end

    def prompt(path, old, findings)
      numbered = old.lines.each_with_index.map { |line, index| format("%5d  %s", index + 1, line) }.join
      listed = findings.map { |f| "- #{f.law} line #{f.line}: #{f.message || f.text.strip}" }
      statements = findings.map(&:law).uniq.map { |id| "#{id}: #{law_statement(id)}" }
      note = Thread.current[RETRY_NOTE]
      [
        "Repair these Law findings in #{path}. Change only what they need.",
        *listed, "", "The Laws:", *statements, "", Scope.note(findings),
        *(note ? ["", "Your previous proposal was refused: #{note}",
                  "Make a smaller change that avoids exactly that, touching only the lines the finding names."] : []),
        "", "Reply with the whole corrected file in one fenced code block and nothing else.", "", numbered
      ].join("\n")
    end

    def law_statement(id) = @laws.find { |law| law.id.to_s == id.to_s }&.policy&.fetch("statement", nil).to_s

    def extract(text)
      body = text.to_s[/```[^\n]*\n(.*?)```/m, 1]
      body&.end_with?("\n") || body.nil? ? body : "#{body}\n"
    end

    # test/**/NAME_test.rb and test/**/test_NAME.rb beside the repaired file.
    def mapped_tests(path)
      name = File.basename(path, ".*")
      return [] if path.start_with?("test/")

      @run.tracked.select { |file| file.start_with?("test/") && File.basename(file).match?(/\A(test_#{name}|#{name}_test)\.rb\z/) }
    end

    def run_test(test)
      @world.exec(RbConfig.ruby, "-Itest", test, timeout: 300).ok?
    end
  end
end
