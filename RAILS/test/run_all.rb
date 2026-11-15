#!/usr/bin/env ruby
# frozen_string_literal: true

# Runs RAILS/test/*_test.rb, one process per file.
#
# The suite was run exactly one way before this: `check-full` did
#
#   Dir["RAILS/test/**/*_test.rb"].sort.each { |f| require File.expand_path(f) }
#
# which loads every contract test into a single process. There are 131 contract
# files today. It works, but the two reasons it works are accidental:
#
#   Constants. Nearly every file declares ROOT, and several declare APPS, CHECKS,
#   LINT and SKIP at class scope. They happen not to collide because they happen
#   to be nested inside differently-named test classes. The first one that is
#   not gets `already initialized constant` on a good day and another file's
#   value on a bad one -- and the failure surfaces as an assertion about the
#   wrong tree, not as a load error.
#
#   Termination. One `exit` or one `abort` anywhere in sixty-nine files ends the
#   run, and Minitest reports on whatever had already been collected. Several of
#   these files shell out to checks that call `exit` on their own failure paths.
#
# There is also nothing local: `check-full` is the release check, so the only way
# to run the contract suite was to run the deploy chain, which shells out to the
# integrity check and the Rails checks and takes minutes. That is why files in this
# directory have been found red on main -- not because nobody ran them, but
# because running them cost a deploy check.
#
#   ruby RAILS/test/run_all.rb                    # all of them
#   ruby RAILS/test/run_all.rb scale              # only files matching /scale/
#   ruby RAILS/test/run_all.rb --jobs 4           # four workers, one process per file each
#   ruby RAILS/test/run_all.rb --json out.json    # machine results alongside the text
#   ruby RAILS/test/run_all.rb --failed-from out.json   # rerun only what was red there
#
# The red ledger. RAILS/test/known_failures.yml registers every file the suite
# may legitimately leave red, with a reason and the environments it applies to.
# A red file without a ledger entry is a regression nobody accepted, and a
# ledger entry whose file went green is a lie the tree tells about itself:
# both fail the run, they are not footnotes. Forty-six standing reds taught
# the tree to ignore red; the ledger is what makes a standing red visible
# again. PUB5_LEDGER=off escapes for an exploratory run. PUB5_SUITE_ENV names
# the environment (default "default", a stripped sandbox "sandbox"): entries
# scoped with envs: apply only where listed, entries without envs everywhere.
#
# Exit status is the number of failing files plus ledger violations, capped at 255.

require "digest"
require "json"
require "rbconfig"
require "tmpdir"
require "yaml"
require_relative "../__shared/lib/shared/subprocess"

module Operator
  class ContractSuite
    TEST_DIR = __dir__
    RAILS_ROOT = File.expand_path("..", __dir__)
    LEDGER = File.join(TEST_DIR, "known_failures.yml")

    # Per file. These read source and assert; a second is generous. The bound is
    # high because four of them shell out to the check runner, which is slow and
    # is a separate problem from this one.
    TIMEOUT = Integer(ENV.fetch("CONTRACT_TIMEOUT", "300"))
    REPLAY = Integer(ENV.fetch("CONTRACT_REPLAY", "0")).clamp(0, 5)

    Outcome = Struct.new(:file, :status, :runs, :assertions, :failures, :output)

    attr_reader :outcomes

    # paths: overrides discovery entirely (the --failed-from rerun). slice:
    # [index, of] runs every of-th file, for --jobs workers; a slice is an
    # internal shape and never checks the ledger, because only a run that saw
    # every file can call a red unregistered.
    def initialize(filter: nil, paths: nil, slice: nil, io: $stdout)
      @filter = filter
      @paths = paths
      @slice = slice
      @io = io
      @outcomes = []
    end

    def files
      # Recursive: test/checks/ is part of the contract suite. This currently
      # selects all 131 files; a narrower glob would make a green result dishonest.
      # Written from the repository root so MASTER/tools/repo/runs.rb reads the glob
      # and counts every file it selects as run. The plugins carry source
      # contracts of their own, so their test trees join the suite here.
      all = @paths ||
            (Dir.glob(File.join(RAILS_ROOT, "..", "RAILS/test/**/*_test.rb")) +
             Dir.glob(File.join(RAILS_ROOT, "..", "RAILS/plugins/*/test/**/*_test.rb")))
                 .map { |path| File.expand_path(path) }.uniq.sort
      all = all.select { |path| path.include?(@filter) } if @filter
      all = all.each_with_index.select { |_, index| index % @slice[1] == @slice[0] }.map(&:first) if @slice
      all
    end

    def run
      list = files
      if list.empty?
        @io.puts("contracts: no test files#{describe_selection}")
        @outcomes = []
        return 1
      end

      @outcomes = list.map do |path|
        outcome = execute(path, seed: replay_seed(path, 0))
        if outcome.status == :pass && REPLAY.positive?
          REPLAY.times do |index|
            replay = execute(path, seed: replay_seed(path, index + 1))
            next if replay.status == :pass

            outcome = Outcome.new(
              rel(path),
              :flake,
              outcome.runs,
              outcome.assertions,
              outcome.failures + replay.failures,
              "initial run passed, replay #{index + 1} did not:\n#{replay.output}"
            )
            break
          end
        end
        report(outcome)
      end
      summarise(@outcomes) unless @slice
      @outcomes.count { |outcome| outcome.status != :pass }.clamp(0, 255)
    end

    private

    def rel(path) = path.sub("#{RAILS_ROOT}/", "")

    def describe_selection
      parts = []
      parts << " matching #{@filter.inspect}" if @filter
      parts << " in slice #{@slice[0]}/#{@slice[1]}" if @slice
      parts.join
    end

    # MT_NO_PLUGINS so a globally installed Minitest plugin cannot change what
    # this observes; -I so a file can require_relative its subject the way the
    # app tests do.
    def replay_seed(path, index)
      Digest::SHA256.hexdigest("#{rel(path)}:#{index}").then { |hex| hex[0, 8].to_i(16) }
    end

    def execute(path, seed: nil)
      env = { "MT_NO_PLUGINS" => "1" }
      command = [RbConfig.ruby, "-I#{TEST_DIR}", path]
      command.concat(["--seed", seed.to_s]) if seed
      out, status = begin
        Shared::Subprocess.capture2e(*command, timeout: TIMEOUT, env:, chdir: RAILS_ROOT)
      rescue Shared::Subprocess::TimeoutError => error
        [error.message, nil]
      end
      build(path, out, status)
    end

    def build(path, out, status)
      summary = out.to_s.lines.filter_map do |line|
        line.match(/\A(\d+) runs, (\d+) assertions, (\d+) failures, (\d+) errors(?:, (\d+) skips)?\s*\z/)
      end.last
      runs, assertions, failures, errors = summary ? summary.captures.first(4).map(&:to_i) : [ 0, 0, 0, 0 ]

      invalid_summary = if summary.nil?
                          "missing valid Minitest summary"
                        elsif runs.zero?
                          "Minitest reported zero runs"
                        elsif failures.positive? || errors.positive?
                          "Minitest reported #{failures} failures and #{errors} errors"
                        end
      output = if invalid_summary
                 "contract runner rejected result: #{invalid_summary}\n#{out}"
               else
                 out.to_s
               end

      state = if status.nil? then :timeout
              elsif !status.success? || invalid_summary then :fail
              else :pass
              end
      Outcome.new(rel(path), state, runs, assertions, failures + errors, output)
    end
    MARK = { pass: "ok  ", fail: "FAIL", timeout: "HUNG", flake: "FLAKE" }.freeze

    def report(outcome)
      @io.puts(format("contracts: %s %-56s %4d runs, %5d assertions",
                      MARK.fetch(outcome.status), outcome.file.sub("test/", ""), outcome.runs, outcome.assertions))
      @io.puts(indent(detail(outcome))) unless outcome.status == :pass
      outcome
    end

    # The failure lines and nothing else. A runner that reprints four hundred
    # lines of backtrace per red file is a runner people stop reading, and the
    # whole reason these tests went unread is that running them was expensive.
    def detail(outcome)
      return "exceeded #{TIMEOUT}s and was killed" if outcome.status == :timeout

      lines = outcome.output.lines
      starts = lines.each_index.select { |i| lines[i].match?(/^\s*\d+\)\s+(Failure|Error):/) }
      return outcome.output.lines.last(4).join.strip if starts.empty?

      starts.first(4).flat_map { |i| lines[i, 4] }.join.rstrip
    end

    def indent(text) = text.to_s.lines.map { |line| "        #{line}" }.join

    def summarise(outcomes)
      red = outcomes.reject { |o| o.status == :pass }
      totals = outcomes.sum(&:runs)
      @io.puts("contracts: #{outcomes.size} file(s), #{totals} runs, #{red.size} red")
      return if red.empty?

      @io.puts("contracts: #{red.map { |o| o.file.sub("test/", "") }.join(', ')}")
    end
  end

  # The ledger check stands apart from the runner because it needs none of its
  # machinery: it reads the outcomes and the register and says what changed
  # hands. Two failure shapes and no others — an unregistered red, and a stale
  # entry — so a malformed ledger shows up as an entry that simply does not
  # match, which the next human fixes by rereading the file.
  module RedLedger
    LEDGER = ContractSuite::LEDGER

    module_function

    def environment = ENV.fetch("PUB5_SUITE_ENV", "default")

    def load
      return {} unless File.file?(LEDGER)

      YAML.safe_load_file(LEDGER, aliases: false).then { |raw| (raw || {}).select { |_, spec| spec.is_a?(Hash) } }
    end

    def applies?(spec, env)
      spec["envs"].nil? || Array(spec["envs"]).include?(env)
    end

    def violations(outcomes)
      return [] if ENV.fetch("PUB5_LEDGER", "") == "off"

      entries = load
      env = environment
      lines = []
      outcomes.reject { |o| o.status == :pass }.each do |outcome|
        spec = entries[outcome.file]
        next if spec && applies?(spec, env)

        lines << if spec
                   "UNREGISTERED HERE #{outcome.file} — the entry is scoped to #{Array(spec["envs"]).join(", ")}; this run is #{env}"
                 else
                   "UNREGISTERED RED #{outcome.file} — register it in RAILS/test/known_failures.yml with a reason, or fix it"
                 end
      end
      outcomes.select { |o| o.status == :pass }.each do |outcome|
        spec = entries[outcome.file]
        next unless spec && applies?(spec, env)

        lines << "STALE LEDGER ENTRY #{outcome.file} — green in #{env}; delete the entry or rescope its envs"
      end
      lines
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  # Positional filter stays first-class (`run_all.rb scale`); flags mix freely.
  filter = nil
  json_path = nil
  failed_from = nil
  jobs = nil
  slice = nil
  argv = ARGV.dup
  while (arg = argv.shift)
    case arg
    when "--json" then json_path = argv.shift
    when "--failed-from" then failed_from = argv.shift
    when "--jobs" then jobs = Integer(argv.shift)
    when "--slice" then slice = [Integer(argv.shift), Integer(argv.shift)] # internal: --jobs workers
    else filter = arg
    end
  end

  write_json = lambda do |path, outcomes, violations|
    next unless path

    File.write(path, JSON.pretty_generate(
                       run_at: Time.now.utc.iso8601,
                       environment: Operator::RedLedger.environment,
                       outcomes: outcomes.map { |o| { file: o.file, status: o.status.to_s, runs: o.runs, assertions: o.assertions, failures: o.failures } },
                       ledger_violations: violations
                     ))
  end

  exit_code =
    if failed_from
      # Rerun only what a previous JSON marked red. The JSON carries repo-relative
      # paths exactly as the ledger and the summary print them, so the selection
      # is by exact path, not by substring hoping.
      previous = JSON.parse(File.read(failed_from))
      red_paths = Array(previous["outcomes"]).select { |o| o["status"] != "pass" }
                                             .map { |o| File.join(Operator::ContractSuite::RAILS_ROOT, o["file"]) }
                                             .select { |path| File.file?(path) }
      if red_paths.empty?
        warn "contracts: nothing red in #{failed_from}"
        exit 0
      end
      warn "contracts: rerunning #{red_paths.size} red file(s) from #{failed_from}"
      suite = Operator::ContractSuite.new(paths: red_paths)
      code = suite.run
      violations = Operator::RedLedger.violations(suite.outcomes)
      violations.each { |line| warn "contracts: #{line}" }
      write_json.call(json_path, suite.outcomes, violations)
      (code + violations.size).clamp(0, 255)
    elsif jobs && jobs > 1 && slice.nil?
      # Workers run slices of the file list and hand the parent a JSON
      # fragment. They spawn through Shared::Subprocess like every file run
      # does — the parent's bound is a backstop; each worker still applies the
      # per-file timeout to its own children. Worker output arrives per worker
      # rather than live, which is the price of bounded capture, and a worker
      # that exceeds it reports as failed rather than hanging the run.
      repo_root = File.expand_path("..", Operator::ContractSuite::RAILS_ROOT)
      list = Operator::ContractSuite.new(filter:).files
      slice_size = (list.size.to_f / jobs).ceil
      fragments = Array.new(jobs) { |index| File.join(Dir.tmpdir, "contracts-#{Process.pid}-#{index}.json") }
      workers = jobs.times.map do |index|
        child = [RbConfig.ruby, __FILE__]
        child << filter if filter
        child += ["--json", fragments[index], "--slice", index.to_s, jobs.to_s]
        begin
          out, status = Shared::Subprocess.capture2e(*child, timeout: (slice_size + 1) * Operator::ContractSuite::TIMEOUT, chdir: repo_root)
          $stdout.write(out)
          status
        rescue Shared::Subprocess::TimeoutError => error
          warn "contracts: worker #{index} exceeded its backstop and was killed: #{error.message}"
          nil
        end
      end
      statuses = workers.map { |w| w && w.success? }
      outcomes = fragments.filter_map { |path| File.file?(path) && JSON.parse(File.read(path))["outcomes"] }
                          .flatten
                          # JSON round-trips the status as a String; the runner's
                          # marks and the ledger both compare Symbols.
                          .map { |o| Operator::ContractSuite::Outcome.new(o["file"], o["status"].to_sym, o["runs"], o["assertions"], o["failures"], "") }
      fragments.each { |path| File.delete(path) if File.file?(path) }
      violations = Operator::RedLedger.violations(outcomes)
      violations.each { |line| warn "contracts: #{line}" }
      write_json.call(json_path, outcomes, violations)
      red = outcomes.count { |o| o.status != :pass }
      clean = statuses.count { |ok| ok == true }
      puts("contracts: #{outcomes.size} file(s) across #{jobs} workers, #{red} red, #{violations.size} ledger violation(s), #{clean}/#{jobs} workers clean")
      (red + violations.size).clamp(0, 255)
    else
      suite = Operator::ContractSuite.new(filter:, slice:)
      code = suite.run
      violations = slice ? [] : Operator::RedLedger.violations(suite.outcomes)
      violations.each { |line| warn "contracts: #{line}" }
      write_json.call(json_path, suite.outcomes, violations)
      (code + violations.size).clamp(0, 255)
    end
  exit(exit_code)
end
