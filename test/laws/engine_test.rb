# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../laws/engine"

class LawEngineTest < Minitest::Test
  include TestHelper

  def teardown = Law.reset!

  def define(id = :SAMPLE, &) = Law.define(id, &)

  def row(**over)
    { "statement" => "s", "kind" => "lexical", "severity" => "error", "lifecycle" => "advisory",
      "autofix" => "never", "enacted" => "2026-11-06", "file" => "laws/sample.rb" }.merge(over.transform_keys(&:to_s))
  end

  def test_fixtures_are_proved_at_load
    define { detect { |l| l.include?("TODO") }; bad "x # TODO\n"; good "x\n"; fix "f" }
    assert_raises(Law::Invalid) { define(:MISSES) { detect { |l| l.include?("TODO") }; bad "nothing\n"; good "x\n" } }
    assert_raises(Law::Invalid) { define(:FLAGS) { detect { |l| l.include?("x") }; bad "x\n"; good "x\n" } }
    assert_raises(Law::Invalid) { define(:BARE) { detect { |l| l.include?("x") } } }
  end

  def test_policy_lives_in_the_index_not_in_ruby
    error = assert_raises(Law::Invalid) { define { severity :error; practice "p" } }
    assert_match(%r{registry/laws.yml}, error.message)
  end

  # The shape of a pub4 Law body (MASTER/law/*.rb) loads unchanged.
  def test_a_pub4_shaped_law_imports_unchanged
    law = define(:BASELINE_LIKE) do
      source "MDN Web Platform Baseline"
      ask "Does a web change depend on a new API without a fallback?"
      fix "Feature-detect and fall back."
      bad "el.style.fieldSizing = %q(content)"
      good "if (CSS.supports(%q(field-sizing), %q(content))) {}"
      tags :DESIGN
    end
    assert_predicate law, :semantic?
    refute_predicate law, :deterministic?
    lexical = define(:LEXICAL_LIKE) do
      pattern ["\\bputs\\b"]
      path "lib/"
      example_path "lib/x.rb"
      bad "puts 1\n"
      good "log 1\n"
      fix "Use the logger."
    end
    assert_equal 1, lexical.scan("puts 1\n# puts\n", "lib/a.rb").size
    assert_empty lexical.scan("puts 1\n", "test/a.rb")
    conduct = define(:DIRECTIVE_LIKE) { practice "Report results and blockers only." }
    refute_predicate conduct, :deterministic?
  end

  def test_check_and_tree_adapters
    law = define(:WITH_ADAPTERS) do
      check { |text, _file| text.include?("bad") ? [finding(line: 1, message: "m")] : [] }
      adapter(:file_names, bad: ["a b.rb"], good: ["a_b.rb"]) { |paths| paths.grep(/ /).map { |p| finding(line: 1, message: p) } }
      bad "bad"
      good "good"
      fix "f"
    end
    assert_equal "m", law.scan("bad", "x.rb").first.message
    assert_equal 1, law.scan_tree(["ok.rb", "not ok.rb"]).size
  end

  def test_enforcement_requires_census_sample_rate_and_ratification
    law = define { detect { |l| l.include?("x") }; bad "x"; good "y"; fix "f" }
    census = { "measured_on" => "2026-11-06", "files" => 10, "findings" => 40, "sampled" => 20,
               "false_positives" => 1, "ratified_by" => "operator" }
    assert_empty Law::Policy.problems("SAMPLE", row(lifecycle: "enforced", census:), law)
    assert_match(/without a census/, Law::Policy.problems("SAMPLE", row(lifecycle: "enforced"), law).join)
    assert_match(/exceeds 5%/, Law::Policy.problems("SAMPLE", row(lifecycle: "enforced", census: census.merge("false_positives" => 2)), law).join)
    assert_match(/sampled 5/, Law::Policy.problems("SAMPLE", row(lifecycle: "enforced", census: census.merge("sampled" => 5)), law).join)
    assert_match(/ratification/, Law::Policy.problems("SAMPLE", row(lifecycle: "enforced", census: census.except("ratified_by")), law).join)
    conduct = define(:CONDUCT) { practice "p" }
    assert_match(/stays advisory/, Law::Policy.problems("CONDUCT", row(lifecycle: "enforced", census:, file: "laws/conduct.rb"), conduct).join)
  end

  def test_load_reconciles_ruby_with_the_index
    sandbox do |root|
      put(root, "sample.rb", "Law.define(:SAMPLE) { practice %q(p) }\n")
      error = assert_raises(Law::Invalid) { Law.load!(dir: root, index: { "laws" => { "OTHER" => row } }) }
      assert_match(/OTHER: indexed but never defined/, error.message)
      assert_match(/SAMPLE: defined but not indexed/, error.message)
      laws = Law.load!(dir: root, index: { "laws" => { "SAMPLE" => row } })
      assert_equal "advisory", laws.first.lifecycle
    end
  end
end

class LawsInForceTest < Minitest::Test
  include TestHelper

  def teardown = Law.reset!

  def tracked = Dir.chdir(Core::ROOT) { Dir.glob("**/*", File::FNM_DOTMATCH).reject { |f| f.start_with?(".git/", "log/") } }

  def test_the_real_laws_load_and_their_fixtures_prove
    ids = Law.load!.map(&:id)
    assert_includes ids, :ONE_IMPLEMENTATION_PER_OPERATION
    assert_includes ids, :GENERATED_FILE_MATCHES_GENERATOR
  end

  def test_one_implementation_per_operation_holds_over_the_tree
    Law.load!
    findings = Law.scan(tracked, laws: [Law[:ONE_IMPLEMENTATION_PER_OPERATION]])
    assert_empty findings.map(&:to_s)
  end

  def test_core_is_where_the_operations_live
    Law.load!
    law = Law[:ONE_IMPLEMENTATION_PER_OPERATION]
    assert_empty law.scan("Net" "::HTTP.start(host)\n", "core/http.rb")
    refute_empty law.scan("Net" "::HTTP.start(host)\n", "master/fix/lane.rb")
  end

  def test_generated_files_match_their_generator
    Law.load!
    findings = Law.scan(%w[AGENTS.md CLAUDE.md], laws: [Law[:GENERATED_FILE_MATCHES_GENERATOR]])
    assert_empty findings.map(&:to_s)
  end
end

class LawLanguageTest < Minitest::Test
  def test_extensionless_ruby_scripts_are_ruby
    assert_equal "ruby", Law.language("bin/master", "#!/usr/bin/env ruby\n")
    assert_nil Law.language("bin/master")
    assert_equal "yaml", Law.language("a.yml")
  end
end
