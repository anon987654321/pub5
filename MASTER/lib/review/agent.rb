# frozen_string_literal: true

require_relative "llm_dispatcher"
require_relative "consensus"
require_relative "prompt_filter"
require_relative "agent/model_selector"
require_relative "agent/model_override"
require_relative "agent/prompt_builder"
require_relative "agent/fallback_chain"
# Conversation and research re-open Master::Review::Agent, split by concern;
# both are registered in data/autoload.yml under reopens_a_constant_defined_elsewhere.
require_relative "agent/conversation"
require_relative "agent/research"

module Master
  module Review
    class Agent
      include PromptFilter
      include ModelSelector
      include ModelOverride
      include PromptBuilder
      include FallbackChain

      DEFAULT_MESSAGE_WINDOW_SIZE = 40

      Dependencies = Data.define(
        :config, :session, :tools, :circuit_breaker, :cache, :bus,
        :model_router, :reasoning_modes, :memory, :personality,
        :code_index, :context_window, :homeostat, :browser_broker
      ) do
        def self.from_kwargs(config:, session:, tools:, circuit_breaker:, cache:,
                             event_bus: nil, model_router: nil, reasoning_modes: nil,
                             memory: nil, personality: nil, code_index: nil,
                             context_window: nil, homeostat: nil, browser_broker: nil)
          new(
            config:, session:, tools:, circuit_breaker:, cache:, bus: event_bus,
            model_router:, reasoning_modes:, memory:, personality:,
            code_index:, context_window:, homeostat:, browser_broker:
          )
        end
      end

      def initialize(deps:)
        @deps = deps
        @config, @session, @tools = deps.config, deps.session, deps.tools
        @circuit_breaker, @cache, @bus = deps.circuit_breaker, deps.cache, deps.bus
        @model_router, @reasoning_modes = deps.model_router, deps.reasoning_modes
        @memory, @personality, @code_index = deps.memory, deps.personality, deps.code_index
        @context_window, @homeostat = deps.context_window, deps.homeostat
        @constitution = nil
        @dispatcher = Master::Review::LLMDispatcher.new(deps:, system_prompt: -> { { static: static_prompt, dynamic: dynamic_prompt } })
      end

      def wire_constitution(constitution) = @constitution = constitution

      # The per-model breaker registry. /fix's LlmRouter asks it which models
      # are open before a repair pass, and the council's two callers check it
      # too; without a reader the router raised, and its rescue reported every
      # candidate open, so every repair pass was skipped.
      def circuit_breaker = @circuit_breaker

      # The container holds no router of its own; /model, model completion and
      # the face's Talk reach the pool through the agent that routes with it.
      def model_router = @model_router

      def ask(prompt, context: nil, operation: nil, image: nil, temperature: nil)
        Thread.current[:master_llm_answer_model] = nil
        messages = Array(context) + [{ role: "user", content: apply_reasoning_mode(prompt) }]
        selected_model = operation ? model_for(operation:) : routed_models.first
        result = @dispatcher.send_with_cache(selected_model, messages, stream: false, image:, temperature:)
        result = retry_on_broke_lane(result, selected_model, messages, image:, temperature:, promote: true)
        record_capability_outcome(operation:, selected_model:, result:)
        remember_answer_model(result, selected_model)
        raise_failure(result)
        result.to_s
      end

      # `operation` names the caller's task so the router can constrain the lane
      # and the outcome is recorded against it; the conversation probe asks by
      # operation, so a bare `model` argument is not enough.
      def ask_once(prompt, system: nil, law: true, model: nil, image: nil, temperature: nil, format: nil,
                   failover: true, operation: nil)
        Thread.current[:master_llm_answer_model] = nil
        messages = [{ role: "user", content: prompt }]
        chosen = model || (operation ? model_for(operation:) : self.model)
        sys = role_system(system, law:)
        result = @dispatcher.send_with_cache(chosen, messages, system: sys, stream: false, image:, temperature:, format:)
        result = retry_on_broke_lane(result, chosen, messages, system: sys, image:, temperature:, promote: model.nil?) if failover
        record_capability_outcome(operation:, selected_model: chosen, result:)
        remember_answer_model(result, chosen)
        raise_failure(result)
        result.to_s
      end

      def consensus
        return @consensus if @consensus && !local_only?

        models = local_only? ? local_consensus_models : nil
        @consensus = Master::Review::Consensus.new(agent: self, event_bus: @bus, models:)
      end

      def wire_context_window(ctx_window)
        @context_window = ctx_window
      end

      private

      def local_only?
        ENV["MASTER_LOCAL_ONLY"] == "1"
      end

      def local_consensus_models
        router = @model_router
        return [] unless router

        models = []
        models.concat(Array(router.local_models)) if router.respond_to?(:local_models)
        models.concat(Array(router.local_server_models)) if router.respond_to?(:local_server_models)
        models.map(&:to_s)
              .reject(&:empty?)
              .reject { |id| id.end_with?(":cloud", "-cloud") }
              .uniq
      end

      # A hop in retry_on_broke_lane answers with the fallback model, not the
      # one routed to; Result::Ok#model (settle's with_model) names whichever
      # one actually produced this result, so recording against selected_model
      # unconditionally would credit or blame the wrong model after a hop.
      def record_capability_outcome(operation:, selected_model:, result:)
        return unless operation && @model_router.respond_to?(:record_capability_outcome)

        effective_model = result.respond_to?(:model) && result.model ? result.model : selected_model
        @model_router.record_capability_outcome(
          model: effective_model, task_type: operation, success: result.is_a?(Master::Result::Ok),
        )
      end

      # Both single-shot doors — ask and ask_once — used to raise on the first
      # broke model. One hop to the claude_code chain head on any category a
      # retry cannot cure; the 2026-08-20 proof runs showed the error-severity
      # rules die in ask (via Attempt) after ask_once was fixed alone.
      def retry_on_broke_lane(result, chosen, messages, system: nil, image: nil, temperature: nil, promote: true)
        return result unless result.is_a?(Master::Result::Err)

        park_failed_single_call(chosen, result)
        outcome = hop_broke_lane_fallbacks(chosen, result, messages, system:, image:, temperature:, promote:)
        return outcome if outcome.is_a?(Master::Result::Ok)

        offline_when_exhausted(outcome, chosen)
      end

      # A lane LaneState refuses (silent, dead, parked, spent) refuses every
      # hop, so walking it would only publish one failover event per model.
      def next_broke_lane_fallback(attempted)
        single_call_fallback_models.reject do |model|
          attempted.include?(model) || !Io::LaneState.usable?(model)
        end.first
      end

      def hop_broke_lane_fallbacks(chosen, first_err, messages, system:, image:, temperature:, promote:)
        last = first_err
        attempted = [chosen]
        loop do
          fallback = next_broke_lane_fallback(attempted)
          break unless fallback

          attempted << fallback
          @bus&.publish("llm:ask_failover", from: chosen, to: fallback, category: last.category)
          hopped = @dispatcher.send_with_cache(fallback, messages, system:, stream: false, image:, temperature:)
          if hopped.is_a?(Master::Result::Ok)
            Thread.current[:master_llm_answer_model] = hopped.model || fallback
            return record_single_call_substitution(chosen, fallback, hopped, promote:)
          end

          last = hopped
          park_failed_single_call(fallback, last)
          break unless last.is_a?(Master::Result::Err)
        end
        last
      end

      # Preserve the actual successful lane for the repair candidate that follows.
      # retry_on_broke_lane records a fallback before returning; the selected model
      # is only the fallback when the dispatcher did not attach Result::Ok#model.
      def remember_answer_model(result, selected_model)
        return Thread.current[:master_llm_answer_model] = nil unless result.is_a?(Master::Result::Ok)

        Thread.current[:master_llm_answer_model] ||= result.model || selected_model
      end
      # A failed one-shot call parks that model for the bounded cache TTL, so
      # the next request does not repeat the same known failure immediately.
      def park_failed_single_call(model, result)
        return unless result.is_a?(Master::Result::Err)

        category = { budget: :quota_exceeded, exhausted: :quota_exceeded, offline: :timeout }.fetch(result.category, result.category)
        Io::ModelSkipCache.skip!(model, reason: result.message, category:)
      end

      # No lane answers: a typed Offline, which every rescue StandardError around a
      # model call already treats as "no model work this pass".
      def raise_failure(result)
        return unless result.is_a?(Master::Result::Err)
        raise Master::Io::LaneHealth::Offline.new(result.message, gap: result.gap) if result.category == :offline

        raise StandardError, result.message
      end

      # Every candidate dead is one condition with one line, not the last lane's error.
      def offline_when_exhausted(last, chosen)
        models = [chosen, *single_call_fallback_models].uniq
        # Down lanes only: a model parked by its own failure answers with that
        # failure, which says more than "offline".
        down = ->(model) { !Io::LaneState.usable?(model, sources: Io::LaneState::DOWN) }
        return last unless last.category == :offline || models.all?(&down)

        offline = Master::Io::LaneHealth.offline_error(models, refuses: down)
        Master::Trace::Dmesg.once("llm0-offline", offline.message)
        Master::Result.err(offline.message, category: :offline, gap: offline.gap)
      end

      def single_call_fallback_models
        return [] unless @model_router.respond_to?(:fallback_chain)

        task_type = @config.task_type.to_s.empty? ? :exploration : @config.task_type.to_sym
        Array(@model_router.fallback_chain(task_type:)).uniq
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Agent.single_call_fallback_models")
        []
      end

      def record_single_call_substitution(from, to, result, promote: true)
        if result.is_a?(Master::Result::Ok)
          promote_runtime_model(from:, to:) if promote
          Io::QuotaCheck.substituted(from:, to:)
        end
        result
      end

      def check_rate_limit(model_id = nil)
        @circuit_breaker.check_rate!(model_id) if @circuit_breaker.respond_to?(:check_rate!)
        nil
      rescue Io::CircuitBreaker::CircuitError => err
        Result.err(err.message, category: err.category)
      end

      def record_trajectory!(message:, model:, outcome:)
        return unless ENV["MASTER_LLM_RECORD"] == "1"

        events = Array(Fiber[:master_trajectory_events]).dup
        events << { "event" => "outcome", "outcome" => outcome, "model" => model.to_s }
        verified = scored_verification(message, model, events, outcome)
        append_trajectory_record(message, model, events, outcome, verified)
      rescue StandardError => e
        @bus&.publish("llm:record_error", error_class: e.class.name, **Master::Execution::Contract.diagnostic_fields(e.message))
      ensure
        Fiber[:master_trajectory_events] = nil
      end

      def scored_verification(message, model, events, outcome)
        Master::AI::Trajectory::Benchmark.score(
          "task" => message.to_s,
          "model" => model.to_s,
          "events" => events,
          "outcome" => outcome,
          "verified" => outcome == "complete",
        )["verified"]
      end

      def append_trajectory_record(message, model, events, outcome, verified)
        Master::AI::Trajectory::Record.new(
          "task" => message.to_s,
          "model" => model.to_s,
          "events" => events,
          "outcome" => outcome,
          "verified" => verified,
        ).append!(File.join(Master::ROOT, ".master", "trajectories", "trajectories.ndjson"))
      end
    end
  end
end
