# frozen_string_literal: true

# The law-fixtures check's half inside the target's process. A ported repo
# loads its OWN law engine here and answers for every fixture pub4 recorded,
# so the two engines never share a process and the port is judged by the
# classes it actually ships, not by pub4's.
#
#   ruby MASTER/tools/law_fixture_runner.rb LAW_DIR FIXTURES_YML
#
# One line of stdout: LAW_FIXTURES_JSON:<json> - the prefix keeps the answer
# readable when the engine or a Law prints on load.
diffs = []
counted = Hash.new(0)
law_dir, fixtures_path = ARGV
law_dir = File.expand_path(law_dir)
result = { "law_dir" => law_dir, "diffs" => diffs, "counted" => counted }

begin
  require File.join(law_dir, "definition")
  ::Law.load_all(law_dir)
rescue StandardError, LoadError => e
  result["error"] = "#{e.class}: #{e.message}"
  puts "LAW_FIXTURES_JSON:#{JSON.dump(result)}"
  exit 3
end

laws = ::Law.definitions
# Psych round-trips symbol keys as Symbols; the contract file speaks string ids.
fixtures = YAML.load_file(fixtures_path).fetch("laws").transform_keys(&:to_s)

fixtures.each do |id, spec|
  status = spec.fetch("status")
  counted[status] += 1

  law = laws[id.to_sym]
  unless law
    diffs << { "id" => id, "detail" => "law not defined in the target engine" }
    next
  end
  # Presence is contracted for every status, not just runnable fixtures: a
  # docs, test or retired record the engine does not name is a dropped law
  # the probe below would never reach.
  next unless status == "fixture"

  file = spec.fetch("file")
  bad = law.send(:scan_main, spec.fetch("bad"), file)
  if bad.empty?
    diffs << { "id" => id, "detail" => "bad fixture not flagged at #{file}" }
  end
  good = law.send(:scan_main, spec.fetch("good"), file)
  if good.any?
    example = good.first.respond_to?(:message) ? good.first.message.to_s : ""
    diffs << { "id" => id, "detail" => "good fixture flagged#{": #{example}" unless example.empty?}" }
  end
end

unrecorded = laws.keys.map(&:to_s).sort - fixtures.keys.sort
unrecorded.each { |id| diffs << { "id" => id, "detail" => "defined but not recorded - re-record the fixtures" } }
result["defined"] = laws.size
diffs.sort_by! { |row| [row.fetch("detail"), row.fetch("id")] }
puts "LAW_FIXTURES_JSON:#{JSON.dump(result)}"
exit(diffs.empty? ? 0 : 1)
