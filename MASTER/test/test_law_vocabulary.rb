# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/law_vocabulary"

class TestLawVocabulary < Minitest::Test
  ROOTS = %w[lib law bin tools].freeze
  FORBIDDEN = [
    /\bRuleFactory\b/,
    /\bRuleHealth\b/,
    /\bRuleDSL\b/,
    /Review::Scan::Rule\b/,
    /Review::Scan::Rules\b/,
    /\bscanner\.rules\b/,
    /\bLaw\.rules\b/,
    /\bRule\s*=\s*Law\b/,
    # Subclassing the old scanner Rule; `rules << Rule.new` in scss_parser is a CSS rule.
    /\bclass\s+\S+\s*<\s*Rule\b/,
  ].freeze

  def files
    ROOTS.flat_map do |root|
      Dir.glob(File.join(Master::ROOT, root, "**", "*")).select { |path| File.file?(path) }
    end.reject { |path| path.include?("/vendor/") || path.include?("/node_modules/") }
  end

  def test_runtime_uses_law_vocabulary
    offenders = files.filter_map do |path|
      # invalid: :replace is not honoured by File.read's kwargs; the scrub is
      # what survives binary files in the scanned roots (woff2, jpg, pdf).
      source = File.read(path, encoding: "UTF-8", invalid: :replace, undef: :replace).scrub
      matches = FORBIDDEN.filter_map { |pattern| pattern.source if source.match?(pattern) }
      matches.empty? ? nil : "#{path.delete_prefix("#{Master::ROOT}/")}: #{matches.join(", ")}"
    end

    assert_empty offenders, "obsolete Rule vocabulary remains:\n#{offenders.join("\n")}"
  end

  def test_normative_forms_converge_on_the_law_vocabulary
    %w[
      rule rules principle principles convention standard guideline heuristic
      doctrine best_practice design_principle engineering_standard
      normative_pattern
    ].each do |term|
      assert_equal "law", Master::LawVocabulary.normalize(term), term
      assert_equal :synonym, Master::LawVocabulary.relation(term), term
    end
  end

  def test_patterns_smells_and_philosophies_remain_distinct_non_normative_concepts
    %w[pattern patterns design_pattern anti-pattern smell code_smell philosophy].each do |term|
      assert_equal :related, Master::LawVocabulary.relation(term), term
      refute_equal "law", Master::LawVocabulary.normalize(term), term
    end
  end

  def test_prompt_explains_the_normative_and_observational_boundary
    prompt = Master::LawVocabulary.prompt

    assert_includes prompt, "synonyms include"
    assert_includes prompt, "Detectors and profiles reference Law IDs"
    assert_includes prompt, "do not create parallel Laws"
  end

  def test_scanner_exposes_laws_not_rules
    scanner = Master::Fix::Scanner.build(root: Master::ROOT)
    assert_respond_to scanner, :laws
    refute_respond_to scanner, :rules
  end
end
