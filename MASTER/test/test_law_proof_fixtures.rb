# frozen_string_literal: true

# The route-contract and CLI-contract suites' rules, for Laws: record what
# every Law's worked examples prove in this checkout, check that a target's
# own law engine - loaded in its own process - still holds them, and never
# let an engine that says nothing about a Law read as a pass. The runnable
# contract is the Law's own detector (scan_main); adapters carry their own
# examples, and those stay with them.

require "minitest/autorun"
require_relative "../tools/law_fixtures"

class TestLawProofFixtures < Minitest::Test
  FixtureLaw = Struct.new(:bad, :good, :proved_by, :main_detector?, :lifecycle, :proof_file, keyword_init: true)

  def with_definitions(fakes)
    original = LawFixtures.method(:registry)
    LawFixtures.define_singleton_method(:registry) { fakes }
    yield
  ensure
    LawFixtures.define_singleton_method(:registry, original)
  end

  def test_a_law_is_recorded_by_its_proofs_shape
    laws = {
      NO_DEBUG: FixtureLaw.new(bad: "puts x", good: "log x", proved_by: nil, main_detector?: true,
                               lifecycle: :active, proof_file: "/repo/app/models/example.rb"),
      SHAPED: FixtureLaw.new(bad: "old bad", good: "old good", proved_by: "test/shaped_test.rb",
                             main_detector?: false, lifecycle: :active, proof_file: "-"),
      ASKED: FixtureLaw.new(bad: nil, good: nil, proved_by: nil, main_detector?: false,
                            lifecycle: :trusted, proof_file: "-"),
      OLD: FixtureLaw.new(bad: "bad", good: "good", proved_by: nil, main_detector?: true,
                          lifecycle: :retired, proof_file: "-"),
    }

    with_definitions(laws) do
      rows = laws.to_h { |id, law| [id.to_s, LawFixtures.row(law)] }

      assert_equal "fixture", rows.fetch("NO_DEBUG").fetch("status")
      assert_equal "/repo/app/models/example.rb", rows.fetch("NO_DEBUG").fetch("file")
      assert_equal "test", rows.fetch("SHAPED").fetch("status")
      assert_equal "test/shaped_test.rb", rows.fetch("SHAPED").fetch("proof")
      assert_equal "docs", rows.fetch("ASKED").fetch("status")
      assert_equal "retired", rows.fetch("OLD").fetch("status")
      assert_equal "bad", rows.fetch("OLD").fetch("bad")
    end
  end

  # The same standard prove! applies when the engine loads: a recorded
  # runnable fixture that does not hold here refuses the record outright.
  def test_a_runnable_fixture_that_holds_nothing_refuses_the_record
    quiet = FixtureLaw.new(bad: "puts x", good: "log x", proved_by: nil, main_detector?: true,
                           lifecycle: :active, proof_file: "-")
    quiet.define_singleton_method(:scan_main) { |_text, _file| [] }

    with_definitions(NO_DEBUG: quiet) do
      spec = { "status" => "fixture", "file" => "-", "bad" => "puts x", "good" => "log x" }
      error = assert_raises(SystemExit) { LawFixtures.verify!("NO_DEBUG" => spec) }

      assert_match(/NO_DEBUG: bad fixture not flagged/, error.message)
    end
  end

  def with_runner(answer)
    original = LawFixtures.method(:run_runner)
    LawFixtures.define_singleton_method(:run_runner) { |_law_dir, _data| answer }
    yield
  ensure
    LawFixtures.define_singleton_method(:run_runner, original)
  end

  # A target that cannot load its engine answers with its error as a diff
  # row, so a port with no Law surface yet is named, never skipped. The fake
  # answers before any process spawns; the live anchor answers for the real
  # spawn.
  def test_an_engine_that_cannot_load_answers_as_a_diff
    with_runner("law_dir" => "/pub5/law", "diffs" => [], "error" => "LoadError: no such file") do
      assert_output(/law engine  LoadError/) do
        diffs = LawFixtures.check(LawFixtures::ROOT)

        assert_equal 1, diffs.size
      end
    end
  end

  def test_a_law_the_target_engine_lost_and_a_law_it_gained_both_name_themselves
    with_runner("law_dir" => "/target/law", "diffs" => [
      { "id" => "NO_DEBUG", "detail" => "law not defined in the target engine" },
      { "id" => "NO_PUTS", "detail" => "defined but not recorded - re-record the fixtures" },
    ], "counted" => { "fixture" => 1 }) do
      assert_output(/NO_DEBUG  law not defined/) do
        diffs = LawFixtures.check(LawFixtures::ROOT)

        assert_equal 2, diffs.size
      end
    end
  end

  def test_the_recorded_contract_covers_what_the_registry_defines
    recorded = YAML.load_file(LawFixtures::DATA).fetch("laws")

    assert_equal 520, recorded.size, "re-record after any Law lands, the file must name every id"
    assert_operator recorded.count { |_id, spec| spec.fetch("status") == "fixture" }, :>=, 250,
                   "the runnable half stopped being recorded"
    recorded.each do |id, spec|
      next unless spec.fetch("status") == "fixture"

      assert_operator spec["bad"].to_s.size, :>, 0, "#{id}: an empty bad example proves nothing"
      assert_operator spec["good"].to_s.size, :>, 0, "#{id}: an empty good example proves nothing"
      assert_operator spec["file"].to_s.size, :>, 0, "#{id}: a fixture without its proof file cannot be re-run"
    end
  end

  # One real anchor: the recorded fixtures come from this checkout's engine,
  # and the whole round-trip - record file, runner, its own engine - is what
  # the check costs.
  def test_the_recorded_contract_matches_this_checkout
    skip if ENV["MASTER_SKIP_LIVE"]

    diffs = LawFixtures.check(LawFixtures::ROOT)

    assert_empty diffs, diffs.first(2).to_s
  end
end
