# frozen_string_literal: true

require_relative "fix_helper"

# What a run holds back before it asks any model: text older than the
# Law's enactment (PLAN.md section 5), and a Law whose repair would reach more
# than 20 files until its census is published (the ASCII_PUNCTUATION lesson).
class FixRunTest < Minitest::Test
  include FixHelper

  def law(enacted: "2026-11-06")
    builder = Law::Builder.new(:TEST_VIOLATION)
    builder.instance_eval do
      detect { |line| line.include?("violation") }
      bad "violation\n"
      good "fine\n"
    end
    builder.build("autofix" => "review", "enacted" => enacted).prove!
  end

  def dry_run(root, laws)
    out = StringIO.new
    code = Fix::Run.new(world: fix_world(root), scope: ".", laws:, model: nil, writer: "operator", dry_run: true, out:).call
    [code, out.string]
  end

  def test_fix_run_has_finite_wall_clock_and_pass_budgets
    assert_equal 3_600, Fix::Run::RUN_BUDGET_S
    assert_equal 180, Fix::Run::STALL_S
    assert_equal 2, Fix::Run::MAX_PASSES
    assert_equal 75, Fix::Repair::FILE_BUDGET_S
  end

  def test_report_is_nonzero_when_a_run_stops_or_a_repair_is_refused
    report_row = Struct.new(:status)
    scan = Struct.new(:findings, :seconds)
    spend = { "tokens_in" => 0, "tokens_out" => 0, "cost_usd" => 0.0, "unpriced_calls" => 0 }

    repo do |root|
      stopped = Fix::Run.new(world: fix_world(root), scope: ".", laws: [], model: nil, writer: "operator",
                             out: StringIO.new, clock: -> { 1.0 })
      stopped.instance_variable_set(:@stopping, "stalled")
      assert_equal 1, stopped.send(:report, 0.0, scan.new([], 0), scan.new([], 0),
                                   [[report_row.new(:stopped), spend]], nil)

      refused = Fix::Run.new(world: fix_world(root), scope: ".", laws: [], model: nil, writer: "operator",
                             out: StringIO.new, clock: -> { 1.0 })
      assert_equal 1, refused.send(:report, 0.0, scan.new([], 0), scan.new([], 0),
                                   [[report_row.new(:refused), spend]], nil)
    end
  end

  def test_text_older_than_the_laws_enactment_is_held
    repo do |root|
      put(root, "old.rb", "violation\n")
      git(root, "add", "-A")
      git(root, "commit", "-q", "-m", "Seed old text", "--date=2020-01-01T00:00:00")
      put(root, "new.rb", "violation\n")
      code, said = dry_run(root, [law])

      assert_equal 0, code
      assert_includes said, "would repair new.rb"
      refute_includes said, "would repair old.rb"
      assert_includes said, "held 1 (predates enactment)"
    end
  end

  def test_a_bulk_law_publishes_its_census_before_any_repair
    repo do |root|
      21.times { |i| put(root, "f#{i}.rb", "violation\n") }
      commit_all(root)
      _, said = dry_run(root, [law])

      assert_includes said, "held 21 (bulk: 21 files, census unpublished)"
      assert_includes said, "census TEST_VIOLATION published"
      assert_match(/\ATEST_VIOLATION: 21 findings in 21 files/, File.read(File.join(root, "tmp/fix/census/TEST_VIOLATION.txt")))
      _, again = dry_run(root, [law])
      assert_includes again, "would repair f0.rb", "a published census lets the Law repair"
    end
  end
end
