# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/convergence/proof"

class TestConvergenceProof < Minitest::Test
  def test_local_proof_reaches_a_truthful_state
    result = Master::Convergence::Proof.run(root: Master::REPO_ROOT)
    assert_includes %i[pass inconclusive], result[:state]
    assert_operator result[:checks].size, :>=, 5
    assert File.file?(result[:receipt][:path])
  end

  STALE = Time.utc(2026, 11, 1, 0, 0, 0).iso8601
  NOW = Time.utc(2026, 11, 8, 12, 0, 0)

  def row(name, state, detail = "")
    { name:, state:, detail: }
  end

  # Receipts store JSON: string keys. Proof reads them back through
  # Receipt.recent, so a fixture that fed symbols would test a shape the
  # pipeline never hands over.
  def stored_row(name, state, detail = "")
    { "name" => name, "state" => state, "detail" => detail }
  end

  def receipt(id, generated_at, checks)
    { "id" => id, "generated_at" => generated_at, "details" => { "checks" => checks } }
  end

  def age(checks, receipts, now: NOW)
    Master::Convergence::Proof.age_inconclusives(checks, receipts:, now: -> { now }, window: 7 * 24 * 60 * 60)
  end

  def test_inconclusive_past_the_window_reopens_as_fail_carrying_the_first_receipt
    stale = receipt("20261101T000000Z-1-aaaa", STALE, [stored_row("wishlist", "inconclusive", "3 anchors need proof")])
    fresh = receipt("20261106T000000Z-1-bbbb", Time.utc(2026, 11, 6).iso8601,
                    [stored_row("wishlist", "inconclusive", "3 anchors need proof")])

    aged = age([row("wishlist", "inconclusive", "3 anchors need proof")], [fresh, stale])

    assert_equal "fail", aged.first[:state]
    assert_includes aged.first[:detail], "20261101T000000Z-1-aaaa"
    assert_includes aged.first[:detail], STALE
    assert_includes aged.first[:detail], "review window closed without a verdict"
  end

  def test_inconclusive_within_the_window_stays_inconclusive
    recent = receipt("20261106T000000Z-1-bbbb", Time.utc(2026, 11, 6).iso8601,
                     [stored_row("wishlist", "inconclusive", "3 anchors need proof")])

    aged = age([row("wishlist", "inconclusive", "3 anchors need proof")], [recent])

    assert_equal "inconclusive", aged.first[:state]
  end

  def test_a_verdict_after_the_inconclusive_restarts_the_clock
    stale = receipt("20261101T000000Z-1-aaaa", STALE, [stored_row("wishlist", "inconclusive", "3 anchors need proof")])
    passed = receipt("20261106T000000Z-1-bbbb", Time.utc(2026, 11, 6).iso8601, [stored_row("wishlist", "pass", "ok")])

    aged = age([row("wishlist", "inconclusive", "3 anchors need proof")], [passed, stale])

    assert_equal "inconclusive", aged.first[:state]
  end

  def test_an_escalated_fail_restarts_the_clock_for_the_next_streak
    stale = receipt("20261101T000000Z-1-aaaa", STALE, [stored_row("wishlist", "inconclusive", "3 anchors need proof")])
    escalated = receipt("20261107T000000Z-1-cccc", Time.utc(2026, 11, 7).iso8601, [stored_row("wishlist", "fail", "aged")])

    aged = age([row("wishlist", "inconclusive", "3 anchors need proof")], [escalated, stale])

    assert_equal "inconclusive", aged.first[:state]
  end

  def test_aging_leaves_pass_and_fail_rows_alone
    stale = receipt("20261101T000000Z-1-aaaa", STALE, [stored_row("trees", "inconclusive", "x")])
    checks = [row("trees", "pass", "present"), row("constitution", "fail", "missing")]

    aged = age(checks, [stale])

    assert_equal [{ name: "trees", state: "pass", detail: "present" },
                  { name: "constitution", state: "fail", detail: "missing" }], aged
  end
end
