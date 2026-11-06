# frozen_string_literal: true

require "json"
require_relative "state"
require_relative "affect"
require_relative "attention"
require_relative "prediction"
require_relative "self_model"

module Cognition
  # A bounded observer. Observations update prediction, attention, affect and
  # self-model state in memory; tick! persists it. Metrics are named for the
  # behaviour they measure and do not imply subjective experience.
  #
  # pub4's Mind subscribed to every event on the bus. pub5 has no bus: the
  # ledger is the record of what a run did, so the mind reads the ledger
  # entries a turn appended (observe_ledger) and the turn's own outcome.
  class Mind
    TICK_EVERY_S = 60
    TICK_EVERY_OBSERVATIONS = 256
    WORKSPACE_HALF_LIFE_S = 900.0
    REFLECT_EVERY = 16

    # The state file through World.
    class Store
      def initialize(world, path = State::PATH)
        @world = world
        @path = path
      end

      def load
        @world.read(@path)
      rescue Errno::ENOENT
        nil
      end

      def save(text) = @world.write(@path, text, mode: 0o600)
    end

    attr_reader :state

    # store: load -> saved text or nil, save(text). memory: remember(key, text, type:).
    def initialize(store:, memory: nil, clock: -> { Time.now.to_i })
      @store = store
      @memory = memory
      @clock = clock
      @state = State.load(store.load)
      @state.metrics["restore_completeness"] = @state.restore_completeness
      @attention = Attention.new
      @affect = Affect.new
      @self_model = SelfModel.new
      @prediction = Prediction.new
      @since_tick = 0
      # From construction, not the saved last_tick_at: that one is from a
      # previous process and would make the first observation of every boot due.
      @ticked_at = @clock.call
      @dirty = false
    end

    def observe(event:, payload: {})
      event = event.to_s
      error = @prediction.observe!(@state.predictions, event:, context: prediction_context(payload))
      salience = @attention.score(event:, payload:, prediction_error: error, affect: @state.affect)
      @affect.update!(@state.affect, prediction_error: error, salience:, **outcome(payload))
      @self_model.update!(@state.self_model, event:, payload:, salience:)
      @state.remember_workspace("key" => "#{event}:#{@clock.call}", "event" => event, "salience" => salience.round(4),
                                "prediction_error" => error.round(4), "at" => @clock.call)
      update_metrics!(salience:, error:)
      @since_tick += 1
      @dirty = true
      tick! if tick_due?
    end

    # Ledger entries as events: an llm call, an effect by verb, a refusal.
    # task_id keeps one turn's entries in one prediction stream.
    def observe_ledger(entries, task_id: nil)
      entries.each do |entry|
        event = case entry["kind"]
                when "llm" then "llm:call"
                when "effect" then "effect:#{entry['verb']}"
                else entry["kind"].to_s
                end
        observe(event:, payload: { task_id:, ok: entry["kind"] == "refusal" ? false : nil }.compact)
      end
    end

    # The only writer. Perception writes nothing; tick decays the working set
    # and saves, and every REFLECT_EVERY ticks the mind reflects.
    def tick!
      decay_workspace!
      @state.tick!
      @since_tick = 0
      @ticked_at = @clock.call
      persist!
      reflect! if (@state.ticks.to_i % REFLECT_EVERY).zero?
      @state.data
    end

    def reflect!
      text = @self_model.reflection(@state.self_model, metrics: @state.metrics, affect: @state.affect)
      @state.think(text, kind: "self_reflection")
      @memory&.remember("cognition/reflection/#{@clock.call}", text, type: "general")
      persist!
      text
    end

    def snapshot = State.deep_dup(@state.data)

    private

    def tick_due?
      return false if @since_tick.zero?

      @since_tick >= TICK_EVERY_OBSERVATIONS || @clock.call - @ticked_at >= TICK_EVERY_S
    end

    # Task-scoped streams when an event carries a correlation id; unscoped
    # events are temporal adjacency only, never causation.
    def prediction_context(payload)
      return unless payload.is_a?(Hash)

      %i[task_id run_id].each do |key|
        value = payload[key] || payload[key.to_s]
        return "work:#{value.to_s.strip[0, 128]}" unless value.nil? || value.to_s.strip.empty?
      end
      nil
    end

    def outcome(payload)
      return {} unless payload.is_a?(Hash)

      success = payload.key?(:ok) ? payload[:ok] : payload["ok"]
      [true, false].include?(success) ? { success: } : {}
    end

    def update_metrics!(salience:, error:)
      @state.metrics["prediction_error"] = (@state.metrics.fetch("prediction_error", 0.0).to_f * 0.9) + (error * 0.1)
      @state.metrics["attention"] = salience
      @state.metrics["workspace_activity"] = workspace_activity
      @state.metrics["restore_completeness"] = @state.restore_completeness
    end

    # A bounded activity and diversity proxy for the working set, not a
    # measure of integrated information or experience.
    def workspace_activity
      active = @state.workspace.sum { |item| item["salience"].to_f }
      kinds = @state.workspace.map { |item| item["event"].to_s }.uniq.size
      span = [State::MAX_WORKSPACE, 1].max
      (((active / span) * 0.55) + ((kinds.to_f / span) * 0.45)).clamp(0.0, 1.0)
    end

    def decay_workspace!
      now = @clock.call
      @state.workspace.each do |item|
        age = [now - item["at"].to_i, 0].max
        item["salience"] = (item["salience"].to_f * Math.exp(-age / WORKSPACE_HALF_LIFE_S)).round(4)
      end
      @state.data["workspace"] = @state.workspace.reject { |item| item["salience"].to_f < 0.03 }
    end

    # Unreadable state is never replaced by defaulted state: the source stays
    # intact for diagnosis.
    def persist!
      return if @state.load_status == "invalid"
      return unless @dirty || @state.ticks.to_i.positive?

      @store.save("#{JSON.pretty_generate(@state.data)}\n")
      @dirty = false
    end
  end
end
