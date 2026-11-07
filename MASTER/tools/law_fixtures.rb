# frozen_string_literal: true

# Law proof fixtures: what every Law's worked examples prove, recorded so a
# port can be held to them. Fourth piece of the pub5 acceptance harness
# (TODO.md, current-revision acceptance): laws.yml moves byte for byte, so the port's law
# engine must fire on the same bad example and stay quiet on the same good one.
#
#   ruby MASTER/tools/law_fixtures.rb record
#   ruby MASTER/tools/law_fixtures.rb check [--root PATH]
#
# record reads the registry this checkout defines (loading it is the same proof
# boot already runs) and refuses when a runnable fixture fails in-process, the
# way Law::Definition#prove! does. check loads the target's own engine in its
# own process (law_fixture_runner.rb) and keeps the same standard there; an
# engine that cannot load answers with its error, not a silent skip.
#
# Only the Law's own detector is contracted: scan_main is "what its bad and
# good prove" (law/definition.rb), without file adapters, whose examples each
# carry their own. Rows the scanner cannot execute (semantic, named-test,
# retired, conduct-only) are recorded for presence: the ported engine must
# still define the same set of ids, and a defined-but-unrecorded Law is a
# diff, not a pass.

require "digest"
require "json"
require "open3"
require "yaml"

module LawFixtures
  ROOT = File.expand_path("../..", __dir__)
  REPOSITORY_NAME = "pub5".freeze
  DIR = File.join(ROOT, "MASTER", "law")
  DATA = File.join(ROOT, "MASTER", "checks", "data", "law_fixtures.yml")
  RUNNER = File.expand_path("law_fixture_runner.rb", __dir__)

  module_function

  # The one seam the registry is read through: the home engine here, a stub
  # in the tests, which never load the engine themselves.
  def registry = ::Law.definitions

  # Every id the catalogue of a checkout must carry, with each Law's proof:
  # the two worked examples and the file they are proved at, or the shape of
  # proof that is not a runnable pair.
  def record
    load_home
    # String ids, so the contract file reads the same on load whatever shape
    # the registry keys take.
    laws = registry.to_h { |id, law| [id.to_s, row(law)] }
    File.write(DATA, YAML.dump({ "schema" => 1, "root" => REPOSITORY_NAME, "laws" => laws }))
    laws
  end

  def load_home
    require_relative "../law/definition"
    ::Law.load_all(DIR)
  end

  def row(law)
    if law.proved_by
      spec = { "status" => "test", "proof" => law.proved_by.to_s }
      spec["bad"] = law.bad.to_s if law.bad
      spec["good"] = law.good.to_s if law.good
      spec
    elsif !law.bad || law.bad.to_s.empty? || !law.main_detector?
      { "status" => "docs" }
    elsif law.lifecycle == :retired
      spec = { "status" => "retired", "file" => law.proof_file }
      spec["bad"] = law.bad.to_s
      spec["good"] = law.good.to_s
      spec
    else
      { "status" => "fixture", "file" => law.proof_file, "bad" => law.bad.to_s, "good" => law.good.to_s }
    end
  end

  # Same standard prove! applies at load, read once more through the public
  # registry so the recorded file cannot contain a fixture pair that does not
  # hold here.
  def verify!(laws)
    failures = laws.filter_map do |id, spec|
      next unless spec["status"] == "fixture"

      law = registry.fetch(id.to_sym) # the registry speaks Symbol ids here
      if law.send(:scan_main, spec.fetch("bad"), spec.fetch("file")).empty?
        "#{id}: bad fixture not flagged at #{spec['file']}"
      elsif law.send(:scan_main, spec.fetch("good"), spec.fetch("file")).any?
        "#{id}: good fixture flagged"
      end
    end
    return if failures.empty?

    abort("law_fixtures: #{failures.size} recorded fixture(s) do not hold in this checkout\n#{failures.join("\n")}")
  end

  # The target's law dir is whatever its layout makes first sense of; a root
  # with none of the known layouts is reported, never skipped.
  def law_dir(root)
    candidates = %w[law laws MASTER/law].map { |rest| File.join(root, rest) }
    found = candidates.find { |candidate| File.file?(File.join(candidate, "definition.rb")) }
    return found if found

    abort("law_fixtures: no law engine under #{root} (tried #{candidates.map { |c| "#{c}/definition.rb" }.join(', ')})")
  end

  def run_runner(law_dir, data)
    out, err, status = Open3.capture3(RbConfig.ruby, RUNNER, law_dir, data)
    line = out.lines.reverse.find { |candidate| candidate.start_with?("LAW_FIXTURES_JSON:") }
    raise "law_fixture_runner answered nothing (exit #{status.exitstatus})\n#{err}" unless line

    JSON.parse(line.delete_prefix("LAW_FIXTURES_JSON:"))
  end

  def check(root)
    recorded = YAML.load_file(DATA).fetch("laws")
    result = run_runner(law_dir(root), DATA)
    diffs = result["diffs"] || []
    # An engine that cannot load answers with its error, not a silent skip.
    diffs << { "id" => "law engine", "detail" => result.fetch("error") } if result.key?("error")
    (result["counted"] || {}).each { |status, count| puts("#{status}: #{count}") }
    puts("defined: #{result['defined']} (recorded #{recorded.size}, #{result['law_dir']})")
    diffs.each { |row| puts("#{row.fetch('id')}  #{row.fetch('detail')}") }
    diffs
  end
end

if $PROGRAM_NAME == __FILE__
  mode = ARGV.first || "check"
  flags = ->(name) { ARGV.include?(name) ? ARGV[ARGV.index(name) + 1] : nil }

  if mode == "record"
    laws = LawFixtures.record
    LawFixtures.verify!(laws)
    counted = laws.values.group_by { |spec| spec.fetch("status") }.transform_values(&:size)
    puts(counted.map { |status, count| "#{status}: #{count}" }.sort.join(", "))
    puts "wrote #{LawFixtures::DATA.delete_prefix("#{LawFixtures::ROOT}/")}"
  else
    target = flags.call("--root") || LawFixtures::ROOT
    diffs = LawFixtures.check(target)
    puts diffs.empty? ? "every Law fixture holds against #{target}" : "#{diffs.size} fixture(s) differ"
    exit(diffs.empty? ? 0 : 1)
  end
end
