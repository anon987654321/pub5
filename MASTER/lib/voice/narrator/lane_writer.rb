# frozen_string_literal: true

module Master
  module Voice
    class Narrator
      # Asks the cheapest live lane of the configured tier for the next beat.
      # Raises Unavailable when no lane can answer; the narrator then speaks
      # from its template and tries again later.
      class LaneWriter
        Unavailable = Class.new(StandardError)

        UNSUPPORTED_LANES = %w[grok-cli codex-cli agy web-chat].freeze

        def initialize(config, lanes: Master::Io::LaneSelection)
          @config = config
          @lanes = lanes
        end

        def call(system:, prompt:, max_tokens:)
          model = pick or raise Unavailable, "no live #{@config["lane_tier"]} lane"
          text = via_ruby_llm(model, system, prompt, max_tokens).to_s.strip
          raise Unavailable, "#{model} answered nothing" if text.empty?

          text
        end

        def pick
          tier = @lanes.tier(@config.fetch("lane_tier", "fast"))
          @lanes.order(tier).find { |id| supported?(id) && @lanes.alive?(id) }
        end

        private

        def supported?(id) = UNSUPPORTED_LANES.none? { |lane| id.start_with?(lane) }

        def via_ruby_llm(model, system, prompt, max_tokens)
          require "ruby_llm"
          chat = RubyLLM.chat(model:).with_instructions(system)
          chat = chat.with_params(max_tokens:) if chat.respond_to?(:with_params)
          chat.ask(prompt).content
        end
      end
    end
  end
end
