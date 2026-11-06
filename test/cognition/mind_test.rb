# frozen_string_literal: true

require "json"
require_relative "../test_helper"
require_relative "../../master/cognition/mind"

# Moved from pub4 test_cognition.rb. Not movable: the two bus cases (the
# `**` subscription reaching namespaced events, and perception publishing
# nothing) test an event bus pub5 does not have, and their job is now
# observe_ledger's; the fix_loop:terminal case tests /fix's outcome receipt
# (FixOutcome), which lands with master/fix.
class MindTest < Minitest::Test
  include TestHelper

  # The state file, in memory.
  class Store
    attr_accessor :text

    def initialize(text = nil) = @text = text
    def load = @text
    def save(text) = @text = text
  end

  class Memory
    attr_reader :rows

    def initialize = @rows = []
    def remember(key, value, type:) = @rows << [key, value, type]
  end

  def mind(store = Store.new, **options) = Cognition::Mind.new(store:, clock: -> { 1_000 }, **options)

  def test_state_built_from_the_frozen_default_is_still_mutable
    state = Cognition::State.new(Cognition::State::DEFAULT)
    state.affect["valence"] = 0.4
    assert_in_delta 0.4, state.affect["valence"]
  end

  def test_attention_rises_with_prediction_error
    attention = Cognition::Attention.new
    affect = Cognition::State.new({}).affect
    low = attention.score(event: "event", payload: {}, prediction_error: 0.05, affect:)
    high = attention.score(event: "event", payload: {}, prediction_error: 1.0, affect:)

    assert_operator high, :>, low
  end

  def test_perception_writes_nothing_until_a_tick
    store = Store.new
    m = mind(store)
    m.observe(event: "turn:answered", payload: { ok: true })
    assert_nil store.text

    m.tick!
    assert_equal 1, JSON.parse(store.text)["ticks"]
  end

  def test_observation_moves_affect_and_the_working_set
    m = mind
    m.observe(event: "turn:answered", payload: { ok: true })

    assert_equal 1, m.snapshot.fetch("workspace").size
    assert_operator m.snapshot.dig("affect", "valence"), :>, 0, "a successful outcome raises valence"
  end

  def test_perception_paces_the_loop
    store = Store.new
    m = mind(store)
    m.observe(event: "llm:call")
    assert_equal 0, m.snapshot.fetch("ticks"), "one observation is not a tick"

    Cognition::Mind::TICK_EVERY_OBSERVATIONS.times { m.observe(event: "llm:call") }
    assert_operator m.snapshot.fetch("ticks"), :>, 0, "the loop runs without a caller"
    refute_nil store.text
  end

  def test_ledger_entries_train_one_turn_stream
    m = mind
    entries = [{ "kind" => "effect", "verb" => "exec" }, { "kind" => "llm" }, { "kind" => "refusal", "verb" => "write" }]
    3.times { |i| m.observe_ledger(entries, task_id: "turn-#{i}") }

    assert_equal "llm:call", Cognition::Prediction.new.expected(m.snapshot.fetch("predictions"),
                                                                event: "effect:exec", context: "work:turn-2")
    assert_operator m.snapshot.dig("affect", "valence"), :<, 0, "a refusal is a failed outcome"
  end

  def test_a_repeated_transition_stops_being_surprising
    model = Cognition::Prediction.new
    predictions = Cognition::State.new({}).predictions

    assert_in_delta 1.0, model.observe!(predictions, event: "chat:message")
    first = model.observe!(predictions, event: "tool:before")
    4.times do
      model.observe!(predictions, event: "chat:message")
      model.observe!(predictions, event: "tool:before")
    end
    model.observe!(predictions, event: "chat:message")
    later = model.observe!(predictions, event: "tool:before")

    assert_in_delta 1.0, first, 0.001, "an unseen pair is fully surprising"
    assert_operator later, :<, 0.5, "a pair seen five times is expected"
    assert_equal "tool:before", model.expected(predictions, event: "chat:message")
  end

  def test_prediction_streams_do_not_cross_train_different_tasks
    model = Cognition::Prediction.new
    predictions = Cognition::State.new({}).predictions
    6.times do
      model.observe!(predictions, event: "repair:start", context: "task-a")
      model.observe!(predictions, event: "test:pass", context: "task-a")
      model.observe!(predictions, event: "repair:start", context: "task-b")
      model.observe!(predictions, event: "test:fail", context: "task-b")
    end

    assert_equal "test:pass", model.expected(predictions, event: "repair:start", context: "task-a")
    assert_equal "test:fail", model.expected(predictions, event: "repair:start", context: "task-b")
    assert_nil model.expected(predictions, event: "repair:start"), "scoped evidence must not leak into the shared stream"
  end

  def test_walk_forward_evaluation_measures_task_scope_against_shared_stream
    training = Array.new(16) do
      [{ context: "task-a", event: "repair:start" }, { context: "task-b", event: "repair:start" },
       { context: "task-a", event: "test:pass" }, { context: "task-b", event: "test:fail" }]
    end.flatten
    testing = Array.new(8) do
      [{ context: "task-a", event: "repair:start" }, { context: "task-a", event: "test:pass" },
       { context: "task-b", event: "repair:start" }, { context: "task-b", event: "test:fail" }]
    end.flatten

    scoped = Cognition::Prediction.evaluate(training:, testing:, scoped: true)
    shared = Cognition::Prediction.evaluate(training:, testing:, scoped: false)

    assert_equal [:measured, :walk_forward, 1.0, 32], scoped.values_at(:state, :protocol, :top1_accuracy, :attempts)
    assert_operator scoped[:top1_accuracy], :>, shared[:top1_accuracy]
  end

  def test_walk_forward_evaluation_is_inconclusive_without_predictive_context
    report = Cognition::Prediction.evaluate(training: [], testing: [{ context: "task-a", event: "repair:start" }])
    assert_equal :inconclusive, report[:state]
  end

  def test_invalid_state_is_preserved_for_diagnosis
    ["not json", JSON.generate("metrics" => "not-a-hash"),
     JSON.generate("predictions" => { "transitions" => { "chat" => "not-a-table" } }),
     JSON.generate("workspace" => ["not-an-entry"]),
     JSON.generate("self_model" => { "performance" => { "bad name" => { "attempts" => 1 } } })].each do |original|
      store = Store.new(original)
      mind(store).tick!
      assert_equal original, store.text, "default state must not silently replace corrupt evidence"
    end
  end

  def test_capability_outcomes_and_calibration_survive_a_restart
    store = Store.new
    m = mind(store)
    m.observe(event: "turn:answered", payload: { task_id: "t7", capability: "code_repair", ok: true, predicted_confidence: 0.9 })
    m.tick!

    measured = Cognition::SelfModel.new.performance(mind(store).snapshot.fetch("self_model"), capability: "code_repair")
    assert_equal [1, 1], measured.values_at(:attempts, :successes)
    assert_in_delta 0.01, measured[:brier_score]
  end

  def test_state_migrates_formula_driven_proxy_metrics
    state = Cognition::State.new({ "identity" => { "continuity" => 1.0 }, "metrics" => { "integration" => 0.9 } })

    refute state.identity.key?("continuity")
    refute state.metrics.key?("integration")
  end

  def test_state_restore_completeness_reports_source_shape
    restored = Cognition::State.load(JSON.generate("identity" => { "name" => "MASTER" }))
    assert_equal "restored", restored.load_status
    assert_operator restored.restore_completeness, :>, 0.0
    assert_operator restored.restore_completeness, :<, 1.0
    assert_equal ["invalid", 0.0], Cognition::State.load("not json").then { |s| [s.load_status, s.restore_completeness] }
  end

  def test_the_learned_expectation_survives_a_restart
    store = Store.new
    first = mind(store)
    6.times do
      first.observe(event: "chat:message")
      first.observe(event: "tool:before")
    end
    first.tick!

    assert_equal "tool:before", Cognition::Prediction.new.expected(mind(store).snapshot.fetch("predictions"), event: "chat:message")
  end

  def test_the_working_set_keeps_the_most_salient_not_the_most_recent
    state = Cognition::State.new({})
    state.remember_workspace("key" => "loud", "salience" => 0.99, "event" => "refusal", "at" => 0)
    20.times { |i| state.remember_workspace("key" => "quiet#{i}", "salience" => 0.1, "event" => "noise", "at" => i) }

    assert_equal Cognition::State::MAX_WORKSPACE, state.workspace.size
    assert_equal "loud", state.workspace.first["key"]
  end

  def test_the_self_model_stays_uncertain_about_consciousness
    memory = Memory.new
    text = mind(memory:).reflect!

    assert_includes text, "unknown about phenomenal consciousness"
    assert_equal "general", memory.rows.first.last
  end

  def test_the_store_writes_owner_only_through_world
    sandbox do |root|
      w = world(root, { read: ["log/master/*"], write: ["log/master/*"] })
      Cognition::Mind.new(store: Cognition::Mind::Store.new(w)).tick!

      assert_equal 0o600, File.stat(File.join(root, Cognition::State::PATH)).mode & 0o777
      assert_equal 1, Cognition::Mind.new(store: Cognition::Mind::Store.new(w)).snapshot["ticks"]
    end
  end
end
