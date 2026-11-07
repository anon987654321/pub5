# frozen_string_literal: true

require "yaml"
require_relative "../test_helper"
require_relative "../../laws/engine"
require_relative "../../master/tools/law_instrument_runner"

class LawInstrumentTest < Minitest::Test
  ROOT = Core::ROOT

  def registry
    @registry ||= Core::Registry.yaml(File.join(ROOT, "registry", "laws.yml")).fetch("laws")
  end

  def test_every_imported_ratchet_and_lint_has_one_named_runtime_instrument
    rows = registry.select { |_id, row| %w[ratchet lint].include?(row["kind"]) }
    expected = Operator::LawInstrumentRunner::RATCHET_IDS + Operator::LawInstrumentRunner::LINT_SPECS.keys
    assert_equal expected.sort, rows.keys.sort

    rows.each do |id, row|
      assert_equal "law_instruments", row.dig("pub4", "instrument"), "#{id} is not routed"
      assert_equal id, row.dig("pub4", "instrument_id"), "#{id} has a mismatched instrument ID"
      proof = row.fetch("proved_by")
      assert_equal "test/laws/law_instruments_test.rb", proof
      assert File.file?(File.join(ROOT, proof)), "#{id} proof target is missing"
      assert_nil row["unported"], "#{id} still has an unported marker"
    end
  end

  def test_law_instrument_runner_is_registered_as_a_bounded_script
    checks = Core::Registry.yaml(File.join(ROOT, "master", "checks", "checks.yml"))
    assert_equal "law_instruments.rb", checks.dig("law_instruments", "script")
    assert File.file?(File.join(ROOT, "master", "checks", "law_instruments.rb"))
  end

  def test_each_imported_law_has_five_distinct_solution_approaches_and_a_selection
    solutions = YAML.safe_load_file(File.join(ROOT, "master", "port", "law_solutions.yml"), aliases: true)
    specific = solutions.fetch("law_specific")
    ids = registry.select { |_id, row| %w[ratchet lint].include?(row["kind"]) }.keys.sort
    assert_equal ids, specific.keys.sort

    ids.each do |id|
      row = specific.fetch(id)
      approaches = row.fetch("alternatives")
      assert_equal 5, approaches.length, "#{id} needs five solution approaches"
      assert_equal 5, approaches.uniq.length, "#{id} repeats an approach"
      refute_empty row.fetch("selected")
      refute_empty row.fetch("rationale")
    end
  end
end
