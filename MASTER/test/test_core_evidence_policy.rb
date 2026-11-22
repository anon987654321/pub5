# frozen_string_literal: true

require "minitest/autorun"
require "master"

# Proof accepts only successful process receipts from registered commands.
# Model-supplied labels are not evidence.
class EvidencePolicyTest < Minitest::Test
  E = Master::Core::Effect
  O = Master::Core::Observation
  PRODUCER_ARGV = {
    test_pass: %w[rake test],
    scan_clean: %w[bin/check],
  }.freeze

  def execution_observation(argv, output: "verified")
    receipt = Master::Core::ExecutionReceipt.from_process(
      argv:, exitstatus: 0, output:, elapsed_ms: 1.0
    )
    O.ok(output, execution_receipt: receipt)
  end

  def proof_with(*kinds)
    proof = Master::Core::Proof.new(risk: :low)
    kinds.each do |kind|
      argv = PRODUCER_ARGV.fetch(kind)
      proof.record_evidence(E.exec(argv), execution_observation(argv))
    end
    proof
  end

  def test_every_scored_kind_has_a_producer
    assert_equal Master::Core::Proof::SCORING.keys.sort, Master::Core::Proof::PRODUCERS.keys.sort
  end

  def test_model_prompt_is_built_from_the_policy_not_restated
    prompt = Master::Core::Model::SYSTEM
    assert_includes prompt, "threshold #{Master::Core::Proof::PASS_THRESHOLD}"
    Master::Core::Proof::SCORING.each do |kind, weight|
      assert_includes prompt, "#{kind}=#{weight}"
    end
    refute_includes prompt, '"evidence":'
    assert_includes prompt, "World records exact successful process receipts"
  end

  def test_exact_command_without_a_world_receipt_scores_nothing
    proof = Master::Core::Proof.new(risk: :low)
    proof.record_evidence(E.exec(%w[rake test]), O.ok("the model says it passed"))
    assert_equal 0, proof.send(:evidence_score)
    refute proof.proved?
  end

  def test_a_successful_but_unregistered_command_scores_nothing
    proof = Master::Core::Proof.new(risk: :low)
    argv = %w[true]
    proof.record_evidence(E.exec(argv), execution_observation(argv))
    assert_equal 0, proof.send(:evidence_score)
    refute proof.proved?
  end

  def test_every_scored_kind_has_a_receipt_producer
    Master::Core::Proof::SCORING.each_key do |kind|
      proof = Master::Core::Proof.new(risk: :low)
      argv = PRODUCER_ARGV.fetch(kind)
      proof.record_evidence(E.exec(argv), execution_observation(argv))
      refute_equal 0, proof.send(:evidence_score), "nothing can earn #{kind}"
    end
  end

  def test_embedded_producer_names_do_not_match
    false_claims = {
      test_pass: [%w[echo rake test], %w[echo bundle exec rake test]],
      scan_clean: [%w[echo rubocop], %w[echo bin/check]],
    }
    false_claims.each do |kind, commands|
      commands.each do |argv|
        proof = Master::Core::Proof.new(risk: :low)
        proof.record_evidence(E.exec(argv), execution_observation(argv))
        assert_equal 0, proof.send(:evidence_score), "#{argv.inspect} forged #{kind}"
      end
    end
  end

  def test_interpreter_and_shell_wrappers_do_not_match_a_producer
    [
      %w[ruby -e puts rake test],
      %w[sh -c rake test],
      %w[bundle exec rake test --extra-task],
    ].each do |argv|
      proof = Master::Core::Proof.new(risk: :low)
      proof.record_evidence(E.exec(argv), execution_observation(argv))
      assert_equal 0, proof.send(:evidence_score), "#{argv.inspect} was not an exact producer"
    end
  end

  def test_receipt_for_a_different_argv_is_rejected
    proof = Master::Core::Proof.new(risk: :low)
    proof.record_evidence(E.exec(%w[bin/check]), execution_observation(%w[rake test]))
    assert_equal 0, proof.send(:evidence_score)
  end

  def test_test_pass_and_clean_scan_reach_the_threshold
    assert proof_with(:test_pass, :scan_clean).proved?
  end

  def test_repeating_one_kind_does_not_stack
    proof = proof_with(:test_pass, :test_pass, :test_pass)
    refute proof.proved?, "repeated test runs counted as independent scan evidence"
  end

  def test_unregistered_exec_invalidates_earlier_evidence
    proof = proof_with(:test_pass, :scan_clean)
    assert proof.proved?
    argv = %w[echo mutate]
    proof.record_evidence(E.exec(argv), execution_observation(argv))
    refute proof.proved?
  end

  def test_recognised_receipt_preserves_the_current_proof_generation
    proof = proof_with(:test_pass, :scan_clean)
    assert proof.proved?
    argv = PRODUCER_ARGV.fetch(:test_pass)
    proof.record_evidence(E.exec(argv), execution_observation(argv))
    assert proof.proved?
  end

  def test_failed_exec_invalidates_earlier_evidence
    proof = proof_with(:test_pass, :scan_clean)
    proof.record_evidence(E.exec(%w[bin/check]), O.no("exit 1"))
    refute proof.proved?
  end

  def test_a_write_invalidates_evidence_earned_before_it
    proof = proof_with(:test_pass, :scan_clean)
    assert proof.proved?
    proof.record_evidence(E.write("MASTER/lib/thing.rb", "CHANGED = 1\n"), O.ok)
    refute proof.proved?
  end

  def test_evidence_re_earned_after_a_write_counts_again
    proof = proof_with(:test_pass, :scan_clean)
    proof.record_evidence(E.write("MASTER/lib/thing.rb", "CHANGED = 1\n"), O.ok)
    refute proof.proved?
    %i[test_pass scan_clean].each do |kind|
      argv = PRODUCER_ARGV.fetch(kind)
      proof.record_evidence(E.exec(argv), execution_observation(argv))
    end
    assert proof.proved?
  end

  def test_a_refused_write_leaves_evidence_and_read_answer_standing
    proof = proof_with(:test_pass, :scan_clean)
    proof.record_evidence(E.write("notes.md", "x\n"), O.no("refused by forbidden_file"))
    assert proof.proved?

    reader = Master::Core::Proof.new
    reader.record_evidence(E.read("notes.md"), O.ok("hello"))
    reader.record_evidence(E.write("notes.md", "x\n"), O.no("refused"))
    assert reader.answered_from_reads?
  end
end
