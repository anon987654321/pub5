# frozen_string_literal: true

require_relative "test_helper"

# data/core_spine.yml#proof_policy, as Master::Proof::Aggregator applies it.
class TestProofAggregator < Minitest::Test
  A = Master::Proof::Aggregator

  def row(mode, status, required: nil, evidence_ok: true)
    { mode:, status:, required:, evidence_ok: }
  end

  def test_fail_wins_over_every_other_status
    rows = [row(:lexical, :pass), row(:visual, :inconclusive), row(:runtime, :fail, required: false)]

    assert_equal :fail, A.aggregate(rows)
  end

  def test_a_required_inconclusive_mode_blocks_pass
    rows = [row(:lexical, :pass), row(:semantic, :inconclusive)]

    assert_equal :inconclusive, A.aggregate(rows)
    assert_equal :inconclusive, A.aggregate([row(:lexical, :pass), row(:visual, :skipped)])
  end

  def test_an_optional_inconclusive_mode_allows_pass
    rows = [row(:lexical, :pass), row(:visual, :inconclusive, required: false)]

    assert_equal :pass, A.aggregate(rows)
  end

  def test_pass_or_fail_with_bad_evidence_is_demoted_to_inconclusive
    assert_equal :inconclusive, A.aggregate([row(:lexical, :pass, evidence_ok: false)])
    assert_equal :inconclusive, A.aggregate([row(:runtime, :fail, evidence_ok: false)])
  end

  def test_empty_is_inconclusive_and_nil_is_inapplicable
    assert_equal :inconclusive, A.aggregate([])
    assert_equal :inapplicable, A.aggregate(nil)
  end

  def test_string_keys_and_values_are_accepted
    rows = [{ "mode" => "lexical", "status" => "pass", "required" => true, "evidence_ok" => true }]

    assert_equal :pass, A.aggregate(rows)
  end

  def test_opt_in_policy_judges_only_rows_marked_required
    rows = [row(:lexical, :pass, required: true), row(:visual, :inconclusive)]

    assert_equal :pass, A.aggregate(rows, policy: :opt_in)
    assert_equal :inconclusive, A.aggregate(rows, policy: :strict_list)
    assert_raises(ArgumentError) { A.aggregate(rows, policy: :lenient) }
  end

  def test_opt_in_with_nothing_required_is_inconclusive_never_pass
    rows = [row(:lexical, :pass), row(:visual, :pass, required: false)]

    assert_equal :inconclusive, A.aggregate(rows, policy: :opt_in)
  end

  def test_subject_roll_up
    assert_equal :inapplicable, A.aggregate_subjects([])
    assert_equal :fail, A.aggregate_subjects(%i[pass inconclusive fail])
    assert_equal :inconclusive, A.aggregate_subjects(%i[pass inconclusive])
    assert_equal :pass, A.aggregate_subjects(%w[pass inapplicable])
    assert_equal :inconclusive, A.aggregate_subjects(%i[pass skipped])
  end
end
