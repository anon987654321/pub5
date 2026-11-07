# frozen_string_literal: true

require_relative "../test_helper"
require "stringio"
require_relative "../../master/commands/laws"

class LawsCommandTest < Minitest::Test
  FakeLaw = Struct.new(:id, :policy, :lifecycle, :severity, :broken, :errors, :detector,
                       :semantic, :findings, :scan_count, keyword_init: true) do
    def enforced? = lifecycle == "enforced"
    def deterministic? = detector
    def semantic? = semantic
    def applies?(_file, _text) = true

    def scan(_text, _file)
      self.scan_count += 1
      findings
    end

    def scan_tree(_paths) = []
  end

  FakeResult = Struct.new(:out)

  class FakeWorld
    def git(*argv)
      output = argv.first == "ls-files" ? "one.rb\0two.rb\0" : "0123456789\n"
      FakeResult.new(output)
    end

    def read(_path) = "fixture\n"
  end

  def fake_law(id, kind:, lifecycle: "advisory", detector: false, semantic: false,
               broken: nil, unported: nil, findings: [])
    policy = { "kind" => kind }
    policy["unported"] = unported if unported
    FakeLaw.new(id:, policy:, lifecycle:, severity: "warning", broken:, errors: [],
                detector:, semantic:, findings:, scan_count: 0)
  end

  def run_census(laws)
    output = StringIO.new
    command = Commands::Laws.new(world: FakeWorld.new, context: "pipe", out: output)
    code = Law.stub(:load!, laws) { command.call(["census", "--all"]) }
    [code, output.string]
  end

  def test_census_accounts_for_every_law_and_only_scans_ready_deterministic_advisories
    laws = [
      fake_law(:ENFORCED, kind: "structural", lifecycle: "enforced", detector: true),
      fake_law(:BROKEN, kind: "lexical", broken: "missing dependency", detector: true),
      fake_law(:UNPORTED, kind: "check", unported: "runtime adapter missing", detector: true),
      fake_law(:RETIRED, kind: "lexical", lifecycle: "retired", detector: true),
      fake_law(:DETERMINISTIC, kind: "structural", detector: true, findings: ["one.rb:1: hit"]),
      fake_law(:SEMANTIC, kind: "semantic", semantic: true),
      fake_law(:CONDUCT, kind: "conduct")
    ]

    code, output = run_census(laws)

    assert_equal 0, code
    assert_equal 0, laws[0].scan_count
    assert_equal 0, laws[1].scan_count
    assert_equal 0, laws[2].scan_count
    assert_equal 0, laws[3].scan_count
    assert_equal 2, laws[4].scan_count
    assert_equal 0, laws[5].scan_count
    assert_equal 0, laws[6].scan_count
    assert_match(/^law: ENFORCED ENFORCED kind=structural census=NOT_RUN$/, output)
    assert_match(/^law: BROKEN BROKEN kind=lexical census=NOT_RUN$/, output)
    assert_match(/^law: UNPORTED UNPORTED kind=check census=NOT_RUN$/, output)
    assert_match(/^law: RETIRED RETIRED kind=lexical census=NOT_RUN$/, output)
    assert_match(/^law: DETERMINISTIC CENSUS_CANDIDATE kind=structural files=2 findings=1 errors=0$/, output)
    assert_match(/^law: SEMANTIC MODEL_REVIEW kind=semantic census=NOT_RUN$/, output)
    assert_match(/^law: CONDUCT HUMAN_REVIEW kind=conduct census=NOT_RUN$/, output)
    assert_match(/laws 7, enforced 1, broken 1, unported 1, retired 1, census candidates 1, model review 1, human review 1/, output)
    assert_match(/CENSUS_CANDIDATE is not ENFORCED/, output)
  end

  def test_a_scanner_error_is_visible_and_counted_instead_of_looking_like_a_clean_law
    law = fake_law(:RAISES, kind: "structural", detector: true)
    law.errors << "adapter failed"

    code, output = run_census([law])

    assert_equal 0, code
    assert_match(/^law: RAISES CENSUS_ERROR kind=structural files=2 findings=0 errors=1$/, output)
    assert_match(/1 scanner errors/, output)
  end

  def test_census_without_an_id_or_all_flag_is_a_usage_error
    output = StringIO.new
    command = Commands::Laws.new(world: FakeWorld.new, context: "pipe", out: output)

    code = Law.stub(:load!, []) { command.call(["census"]) }

    assert_equal 64, code
    assert_match(/usage: bin\/master laws/, output.string)
  end
end
