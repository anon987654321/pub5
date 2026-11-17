# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/fix/adaptive_journey"

class TestAdaptiveJourney < Minitest::Test
  def evidence
    [
      { id: "trace-1", verified: true },
      { id: "test-1", verified: true },
      { id: "receipt-1", verified: true },
      { id: "unverified", verified: false },
    ]
  end

  def routes
    [
      { id: "symptom", actions: ["patch each failing test"], evidence_ids: %w[trace-1],
        impact: 0.5, confidence: 0.7, cost: 4, risk: 0.5, reversibility: "moderate" },
      { id: "root-cause", actions: ["trace deployment lifecycle"], evidence_ids: %w[trace-1 test-1 receipt-1],
        impact: 0.95, confidence: 0.9, cost: 1, risk: 0.1, reversibility: "easy" },
    ]
  end

  def test_selects_high_leverage_grounded_route
    decision = Master::Fix::AdaptiveJourney.new.choose(
      routes:, verified_evidence: evidence, objective: "deployment"
    )
    assert_equal "root-cause", decision.route.id
    assert_operator decision.score, :>, 0
    assert_equal "symptom", decision.alternatives.first.fetch(:id)
  end

  def test_unverified_and_inconclusive_outcomes_never_reinforce
    planner = Master::Fix::AdaptiveJourney.new
      .observe(route_id: "root-cause", status: "PASS", evidence_id: "", verified: true)
      .observe(route_id: "root-cause", status: "INCONCLUSIVE", evidence_id: "receipt-1", verified: true)
    assert planner.history.none? { |row| row.fetch("verified") }
    assert planner.history.all? { |row| row.fetch("reinforcement").zero? }
  end

  def test_only_verified_terminal_evidence_reinforces
    planner = Master::Fix::AdaptiveJourney.new.observe(
      route_id: "root-cause", status: "PASS", evidence_id: "receipt-1", verified: true
    )
    assert_equal 1.0, planner.history.first.fetch("reinforcement")
    refute_same planner, planner.observe(
      route_id: "root-cause", status: "FAIL", evidence_id: "receipt-1", verified: true
    )
  end

  def test_rejects_routes_without_verified_evidence
    error = assert_raises(ArgumentError) do
      Master::Fix::AdaptiveJourney.new.choose(
        routes: [{ id: "guess", actions: ["rewrite everything"], evidence_ids: ["unverified"],
          impact: 1, confidence: 1, cost: 1, risk: 0, reversibility: "easy" }],
        verified_evidence: evidence, objective: "repair"
      )
    end
    assert_match(/no route has grounded evidence/, error.message)
  end

  def test_causal_graph_uses_only_explicit_edges_between_known_nodes
    graph = Master::Fix::AdaptiveJourney.new.causal_graph([
      { id: "source", kind: "failure", status: "FAIL" },
      { id: "repair", kind: "change", status: "PASS", caused_by: ["source", "missing", "repair"] },
    ])
    assert_equal [["source", "repair"]], graph.fetch("edges")
    assert_equal ["source"], graph.fetch("roots")
  end

  def test_rejects_unknown_outcome_states
    assert_raises(ArgumentError) do
      Master::Fix::AdaptiveJourney.new.observe(
        route_id: "x", status: "GREEN", evidence_id: "proof", verified: true
      )
    end
  end
end
