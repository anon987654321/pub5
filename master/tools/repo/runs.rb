# frozen_string_literal: true

# Which entrypoint runs a given file, and which files nothing runs.
#
# "Does anything read this?" is the question that takes an afternoon in this
# repo and should take a second. amber's architecture record was deleted and
# nothing noticed because nothing read it; four rails scanners stopped seeing 57
# views when the verticals moved to engines, and the falling finding count read
# as improvement. Both are the same question, unasked.
#
#   ruby master/tools/runs.rb                 # coverage summary + orphans
#   ruby master/tools/runs.rb --who <path>    # which entrypoints reach a file
#   ruby master/tools/runs.rb --json
#
# Reachability is computed, not declared: the globs come out of the runner files
# themselves, so a glob that changes in the Rakefile changes the answer here
# without anyone updating a list. The only declared part is CONVENTIONS, for
# runners whose glob lives inside a framework rather than in this repo.

require "json"
require_relative "../../lib/trace/dmesg"

module Operator
  class Runs
    ROOT = File.expand_path("../../..", __dir__)

    # Files that orchestrate other files. Each is read for glob literals.
    RUNNERS = %w[
      master/Rakefile
      master/tools/Rakefile
      master/bin/check
      master/bin/ci
      master/web/bin/ci
      openbsd/bin/check
      openbsd/bin/check-rails
      openbsd/bin/check-openbsd
      openbsd/bin/check-vps
      openbsd/test/run_all.rb
      rails/test/run_all.rb
      rails/package.json
      master/tools/rails/premerge.rb
      studio/Rakefile
      master/checks/runner.rb
      master/checks/release.rb
    ].freeze

    # `rails test` globs inside the framework, not in any file here. An app's
    # bin/ci reaching its own test tree is a convention, so it is written down
    # rather than inferred -- and named as an assumption, because an assumption
    # that looks like a measurement is how a check ends up measuring nothing.
    CONVENTIONS = {
      "rails/amber/bin/ci" => ["rails/amber/test/**/*_test.rb"],
      "rails/brgen/bin/ci" => [
        "rails/brgen/test/**/*_test.rb",
        "rails/brgen/engines/*/test/**/*_test.rb",
        "rails/brgen_*/test/**/*_test.rb",
        "rails/brgen_*/*/test/**/*_test.rb",
        "rails/brgen_*/engines/*/test/**/*_test.rb",
        "rails/__shared/test/**/*_test.rb",
      ],
      "rails/bsdports/bin/ci" => ["rails/bsdports/test/**/*_test.rb"],
      "master/web/bin/ci" => ["master/web/test/**/*_test.rb"],
      "rails/mrdamascy/bin/ci" => ["rails/mrdamascy/test/**/*_test.rb"],
      # These runners construct their Node inventory from a runtime path variable
      # or invoke npm script names; the complete target glob is therefore explicit.
      "master/bin/check" => ["master/web/test/**/*.test.mjs"],
      "master/tools/rails/premerge.rb" => [
        "rails/test/pwa_offline_store.test.mjs",
        "rails/test/stimulus_components_runtime_contract.test.mjs",
      ],
      # studio's Rakefile builds this path from separate File.join arguments,
      # so the source-glob reader cannot recover the directory on its own.
      "studio/Rakefile" => ["studio/test/*_test.rb"],
    }.freeze

    # npm scripts name their test files inside `node --test ...` strings, so no
    # literal survives the source-glob reader. These runners are parsed as JSON
    # and every script value that names a test file counts as its runner.
    JSON_RUNNERS = %w[rails/package.json].freeze

    # Support files named like tests. A runner loads these; nothing runs them.
    HELPERS = %w[test_helper.rb test_defaults.rb test_support.rb].freeze

    # A string literal that looks like it selects ruby files.
    GLOB = /["']([A-Za-z0-9_.\-\/*\[\]{}]*\*[A-Za-z0-9_.\-\/*\[\]{}]*\.rb)["']/

    # A runner naming one file outright runs it just as surely. tools/Rakefile
    # lists test_tools_check.rb by name — deliberately, its comment says, because
    # the glob beside it would pull in the dilla and tool suites — and a
    # glob-only extractor read that as a test nothing runs. A path literal that
    # matches no test file matches nothing here, so this cannot invent coverage.
    EXACT = %r{["']((?:[A-Za-z0-9_.\-]+/)*(?:test|spec)/[A-Za-z0-9_.\-]+\.(?:rb|mjs|sh))["']}

    def self.globs
      @globs ||= begin
        found = Hash.new { |hash, key| hash[key] = [] }

        RUNNERS.each do |runner|
          path = File.join(ROOT, runner)
          next unless File.file?(path)

          base = runner.split("/").first
          source = File.read(path)
          (source.scan(GLOB).flatten + source.scan(EXACT).flatten).uniq.each do |glob|
            # Globs are written relative to the tree the runner lives in.
            found[runner] << (glob.start_with?("master/", "rails/", "openbsd/", "master/tools/") ? glob : "#{base}/#{glob}")
          end
        end

        CONVENTIONS.each { |runner, list| found[runner].concat(list) }
        JSON_RUNNERS.each do |runner|
          base = runner.split("/").first
          package = JSON.parse(File.read(File.join(ROOT, runner)))
          (package["scripts"] || []).each_value.flat_map { |line| line.scan(/[\w.\/-]+\.test\.mjs/) }.uniq.each do |path|
            found[runner] << File.join(base, path)
          end
        end
        found
      end
    end

    # A test is a file under a test/ directory, not every file whose
    # name reads like one. The name alone was the first instrument and it was
    # wrong in both directions: law/ rules are named for what they detect, so
    # squint_test.rb read as a test (exempted by hand), master/tools/test_naming.rb
    # is the lint over test names and read as an orphan test forever, and
    # lib/review/scan/self_test.rb read as a test that happened to be covered by
    # a bin/check glob — a false positive masked by a coincidence, which is the
    # worse half. Three files, all of them source. Adding a third exemption by
    # hand was the move this replaces, because the exemptions were describing a
    # rule the directory already states.
    #
    # 726 of the 729 files named like tests are under test/; the three
    # that are not are those three. HELPERS stays: test_helper.rb IS under test/,
    # and a runner loads it rather than running it.
    TEST_DIR = %r{(?:\A|/)test/}

    def self.test_files
      # The census covers language-neutral test inventories, not just Ruby.
      # The prior .rb-only glob omitted 23 Node runtime tests and OpenBSD's
      # resource-guard shell test; those can be orphaned while the count stays green.
      patterns = %w[**/*.rb **/*.test.mjs **/test_*.sh **/*_test.sh]
      @test_files ||= %w[master rails openbsd studio].flat_map do |tree|
        patterns.flat_map { |pattern| Dir[File.join(ROOT, tree, pattern)] }
      end.uniq
       .map { |path| path.sub("#{ROOT}/", "") }
       .reject { |path| path =~ %r{/(node_modules|vendor|tmp|\.master|knowledge|output)/} }
       .select { |path| path =~ TEST_DIR }
       .select do |path|
         File.basename(path).match?(/\Atest_.*\.rb\z|_test\.rb\z|_spec\.rb\z|\A.*\.test\.mjs\z|\A(?:test_.*|.*_test)\.sh\z/)
       end
       .reject { |path| HELPERS.include?(File.basename(path)) }
       .sort
    end

    def self.who_runs(file)
      globs.select { |_, list| list.any? { |glob| File.fnmatch?(glob, file, File::FNM_PATHNAME | File::FNM_EXTGLOB) } }
           .keys
    end

    def self.run
      reached = {}
      test_files.each { |file| reached[file] = who_runs(file) }
      orphans = reached.select { |_, runners| runners.empty? }.keys

      {
        tests: reached.size,
        reached: reached.size - orphans.size,
        orphans:,
        runners: globs.transform_values(&:sort),
      }
    end
  end
end

if $PROGRAM_NAME == __FILE__
  if (index = ARGV.index("--who"))
    target = ARGV[index + 1]
    unless target
      Master::Trace::Dmesg.status("runs0", "usage, runs.rb --who <path>", io: $stderr)
      exit 64
    end
    runners = Operator::Runs.who_runs(target)
    Master::Trace::Dmesg::Report.print("runs0", runners.empty? ? "nothing runs #{target}" : runners.join("\n"))
    exit(runners.empty? ? 1 : 0)
  end

  report = Operator::Runs.run

  if ARGV.include?("--json")
    puts JSON.pretty_generate(report)
  else
    Master::Trace::Dmesg.attach("runs0", "master0", "#{report[:reached]}/#{report[:tests]} test files reachable from an entrypoint")
    unless report[:orphans].empty?
      Master::Trace::Dmesg.status("runs0", "nothing runs these")
      report[:orphans].each { |file| Master::Trace::Dmesg.status("runs0", file) }
    end
  end

  exit(report[:orphans].empty? ? 0 : 1)
end
