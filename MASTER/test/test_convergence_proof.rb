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

  # --- inconclusive_aging: an INCONCLUSIVE cannot settle into permanent amber --

  def write_receipt(root:, id:, generated_at:, checks:)
    directory = File.join(root, ".master", "receipts")
    FileUtils.mkdir_p(directory)
    payload = {
      schema: 1, id: id, command: "convergence.prove", state: "inconclusive",
      generated_at: generated_at.iso8601, git: {}, inventory: {}, details: { checks: checks },
    }
    File.write(File.join(directory, "convergence-#{id}.json"), JSON.pretty_generate(payload))
  end

  def aged_fixture_root
    now = Time.now.utc
    Dir.mktmpdir("aging-proof-").tap do |root|
      FileUtils.mkdir_p(File.join(root, "MASTER", "data"))
      File.write(File.join(root, "MASTER", "data", "soul.yml"), "---\n")
      File.write(File.join(root, "MASTER", "data", "laws.yml"), "---\n")
      %w[MASTER RAILS OPENBSD STUDIO].each { |tree| FileUtils.mkdir_p(File.join(root, tree)) }
      # wishlist runs against MASTER/convergence.yml — absent here, so it degrades
      # honestly; the aging rows below are what this fixture exists to prove.
      @now = now
    end
  end

  def test_a_dated_inconclusive_past_its_window_reopens_as_fail
    root = aged_fixture_root
    old = @now - 20 * 86_400
    write_receipt(root:, id: "20260101T000000Z-old-1", generated_at: old,
                  checks: [ { "name" => "commands", "state" => "inconclusive", "detail" => "not probed" } ])

    result = Master::Convergence::Proof.check_aging(root, now: @now)

    assert_equal "fail", result[:state]
    assert_match(/commands.*receipt 20260101T000000Z-old-1/, result[:detail])
  end

  def test_a_recent_inconclusive_is_still_a_wait_not_a_fail
    root = aged_fixture_root
    write_receipt(root:, id: "20260102T000000Z-new-1", generated_at: @now - 2 * 86_400,
                  checks: [ { "name" => "commands", "state" => "inconclusive", "detail" => "not probed" } ])

    result = Master::Convergence::Proof.check_aging(root, now: @now)

    assert_equal "pass", result[:state]
  end

  def test_a_verdict_after_the_inconclusive_clears_it
    root = aged_fixture_root
    write_receipt(root:, id: "20260101T000000Z-old-2", generated_at: @now - 20 * 86_400,
                  checks: [ { "name" => "commands", "state" => "inconclusive", "detail" => "not probed" } ])
    write_receipt(root:, id: "20260102T000000Z-verdict-1", generated_at: @now - 3 * 86_400,
                  checks: [ { "name" => "commands", "state" => "pass", "detail" => "answered" } ])

    result = Master::Convergence::Proof.check_aging(root, now: @now)

    assert_equal "pass", result[:state]
  end

  def test_a_check_that_went_inconclusive_again_starts_its_own_window
    root = aged_fixture_root
    write_receipt(root:, id: "20260101T000000Z-old-3", generated_at: @now - 30 * 86_400,
                  checks: [ { "name" => "commands", "state" => "inconclusive", "detail" => "first wait" } ])
    write_receipt(root:, id: "20260102T000000Z-verdict-2", generated_at: @now - 20 * 86_400,
                  checks: [ { "name" => "commands", "state" => "pass", "detail" => "answered" } ])
    write_receipt(root:, id: "20260103T000000Z-new-2", generated_at: @now - 2 * 86_400,
                  checks: [ { "name" => "commands", "state" => "inconclusive", "detail" => "second wait" } ])

    result = Master::Convergence::Proof.check_aging(root, now: @now)

    assert_equal "pass", result[:state], "the second wait is young; the first was answered"
  end

  def test_a_verdict_before_an_inconclusive_does_not_clear_it
    root = aged_fixture_root
    write_receipt(root:, id: "20260101T000000Z-verdict-3", generated_at: @now - 30 * 86_400,
                  checks: [ { "name" => "trees", "state" => "pass", "detail" => "answered" } ])
    write_receipt(root:, id: "20260102T000000Z-old-4", generated_at: @now - 20 * 86_400,
                  checks: [ { "name" => "trees", "state" => "inconclusive", "detail" => "unanswered since" } ])

    result = Master::Convergence::Proof.check_aging(root, now: @now)

    assert_equal "fail", result[:state]
    assert_match(/receipt 20260102T000000Z-old-4/, result[:detail], "the FAIL cites the receipt that first dated the row")
  end

  def test_run_carries_the_aging_check
    result = Master::Convergence::Proof.run(root: Master::REPO_ROOT)

    aging = result[:checks].find { |row| row[:name] == "aging" }
    refute_nil aging, "run() must measure the aging of its own INCONCLUSIVE rows"
    assert_includes %w[pass fail inconclusive], aging[:state]
  end
end
