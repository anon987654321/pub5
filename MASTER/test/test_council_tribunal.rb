# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/review/council/evidence"
require_relative "../lib/review/council/tribunal"

class TestCouncilTribunal < Minitest::Test
  Evidence = Master::Review::Council::Evidence

  def test_evidence_preserves_inconclusive
    evidence = Evidence.new(
      artifact: "face",
      domain: :visual,
      status: :inconclusive,
    )

    assert evidence.inconclusive?
    refute evidence.actionable?
  end

  def test_evidence_is_actionable_only_with_observation_and_anchor
    evidence = Evidence.new(
      artifact: "chat",
      domain: :ui,
      observations: ["button overlaps the footer"],
      anchors: ["button[data-action=send]"],
    )

    assert evidence.actionable?
  end

  def test_evidence_rejects_unknown_status
    assert_raises(ArgumentError) do
      Evidence.new(artifact: "x", domain: :general, status: :guess)
    end
  end

  def test_inconclusive_review_does_not_call_personas
    agent = Minitest::Mock.new
    tribunal = Master::Review::Council::Tribunal.new(agent:)

    result = tribunal.review(
      evidence: [
        Evidence.new(
          artifact: "audio",
          domain: :sound,
          status: :inconclusive,
        ),
      ],
      personas: [],
      context: "test",
    )

    assert result.ok?
    assert_equal :inconclusive, result.value![:status]
    assert_empty result.value![:feedback]
    agent.verify
  end

  def test_tribunal_forwards_mandatory_veto_roles_to_deliberation
    requested = nil
    deliberation = Object.new
    deliberation.define_singleton_method(:review_convergent) do |_payload, context:, image:, required_veto_roles:|
      requested = required_veto_roles
      Master::Result.ok([{ persona: "Security", role: "Security Review", veto_role: true }])
    end
    evidence = Evidence.new(
      artifact: "code",
      domain: :general,
      status: :observed,
      observations: ["an actionable code change"],
      anchors: ["MASTER/lib/example.rb:1"],
    )

    result = Master::Review::Council::Deliberation.stub(:new, ->(**_options) { deliberation }) do
      Master::Review::Council::Tribunal.new(agent: Object.new).review(
        evidence:,
        personas: [],
        context: "general critique",
        required_veto_roles: ["Security"],
      )
    end

    assert result.ok?
    assert_equal ["Security"], requested
  end

  def test_comparison_requires_matched_observed_evidence
    attributes = { artifact: "mix", domain: :sound, observations: ["measured"],
                   anchors: ["mix"], provenance: { probe: "peak", conditions: { sample_rate: 48_000 } } }
    before = Evidence.new(**attributes, measurements: { peak: 0.9 })
    after = Evidence.new(**attributes, measurements: { peak: 0.8 })
    result = before.compare(after)
    assert_equal :observed, result[:status]
    assert_in_delta(-0.1, result[:deltas][:peak])
    refute result.key?(:winner)
    assert_equal :inconclusive, before.compare(after.with(status: :failed))[:status]
    assert_equal :inconclusive, before.compare(after.with(provenance: {}))[:status]
  end

  def test_comparison_receipt_requires_fingerprints_and_binds_observations
    conditions = { sample_rate: 48_000 }
    base = { artifact: "mix", domain: :sound, observations: ["measured"], anchors: ["mix"] }
    provenance = { probe: "peak", conditions: }
    before = Evidence.new(**base, measurements: { peak: 0.9 }, provenance: provenance.merge(artifact_sha256: "a" * 64))
    after = Evidence.new(**base, measurements: { peak: 0.8 }, provenance: provenance.merge(artifact_sha256: "b" * 64))
    result = before.comparison_receipt(after)
    assert_equal :observed, result[:status]
    assert_equal Digest::SHA256.hexdigest(result[:receipt][:content]), result[:receipt][:sha256]
    assert_equal :inconclusive, before.comparison_receipt(after.with(provenance:))[:status]
    refute result.key?(:winner)
  end

  def test_failed_probes_do_not_convene_the_council
    evidence = Evidence.new(artifact: "render", domain: :design, status: :failed)
    result = Master::Review::Council::Tribunal.new(agent: Object.new).review(evidence:, personas: [], context: "test")
    assert result.ok?
    assert_equal :inconclusive, result.value![:status]
  end

  def test_hash_evidence_is_normalized
    result = Master::Review::Council::Tribunal.new(agent: Object.new).send(
      :normalize,
      {
        artifact: "code",
        domain: "general",
        status: "observed",
        observations: ["x"],
        anchors: ["MASTER/lib/example.rb:1"],
      },
    )

    assert_equal :observed, result.first.status
    assert_equal :general, result.first.domain
  end
end
