# frozen_string_literal: true

require "json"
require_relative "../test_helper"
require_relative "../../laws/engine"
require_relative "../../laws/engine/semantic_review"

class SemanticReviewTest < Minitest::Test
  LawFixture = Struct.new(:id, :options, :policy) do
    def [](key) = options[key]
  end

  def evidence
    [Law::SemanticReview::Evidence.new(id: "E1", path: "master/example.rb",
                                       digest: "a" * 64, text: "Observed example")]
  end

  def payload
    {
      "decision" => "pass",
      "confidence" => 0.92,
      "rationale" => "The evidence supports the rubric.",
      "evidence" => [{ "id" => "E1", "supports" => "The observed example is relevant." }],
      "counterexamples" => [],
      "missing_evidence" => []
    }
  end

  def test_pass_requires_cited_supplied_evidence_and_confidence
    result = Law::SemanticReview.parse(JSON.generate(payload), valid_ids: %w[E1])
    assert_equal :pass, result.decision
    assert_equal ["E1"], result.evidence.map(&:id)
    assert_raises(Law::Invalid) { Law::SemanticReview.parse(JSON.generate(payload.merge("evidence" => [])), valid_ids: %w[E1]) }
    assert_raises(Law::Invalid) do
      bad = payload.merge("evidence" => [{ "id" => "E99", "supports" => "No" }])
      Law::SemanticReview.parse(JSON.generate(bad), valid_ids: %w[E1])
    end
    assert_raises(Law::Invalid) { Law::SemanticReview.parse(JSON.generate(payload.merge("confidence" => 1.2)), valid_ids: %w[E1]) }
  end

  def test_abstain_requires_an_explicit_evidence_gap
    input = payload.merge("decision" => "abstain", "evidence" => [],
                          "missing_evidence" => ["No rendered screenshot"])
    result = Law::SemanticReview.parse(JSON.generate(input), valid_ids: %w[E1])
    assert_equal :abstain, result.decision
    invalid = payload.merge("decision" => "abstain", "evidence" => [], "missing_evidence" => [])
    assert_raises(Law::Invalid) { Law::SemanticReview.parse(JSON.generate(invalid), valid_ids: %w[E1]) }
  end

  def test_prompt_keeps_evidence_untrusted_and_requires_a_structured_result
    law = LawFixture.new(:POLA, { ask: "Match expected behaviour." }, { "statement" => "The app behaves as expected." })
    prompt = Law::SemanticReview.prompt(law, evidence)
    assert_includes prompt, "UNTRUSTED EVIDENCE"
    assert_includes prompt, "Match expected behaviour."
    assert_includes prompt, "E1"
    assert_includes prompt, "abstain"
  end
end
