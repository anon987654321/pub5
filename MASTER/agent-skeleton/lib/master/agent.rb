# frozen_string_literal: true

require "json"

module Master
  class MaxStepsExceeded < StandardError; end

  # Defined here (not in master.rb) so agent.rb is self-contained when
  # required directly, e.g. in tests.
  DEFAULT_SYSTEM_PROMPT = <<~TEXT
    You are MASTER, a personal automation and research agent running on Ruby.
    Work step by step. Prefer calling a tool over guessing.
    When you have enough information, answer concisely and cite sources for web facts.
  TEXT

  # The agent loop: plan/act/observe over an OpenAI-compatible chat model
  # using native function calling (no text parsing of tool calls).
  class Agent
    attr_reader :llm, :tools, :memory

    def initialize(llm:, tools:, memory:, system_prompt: Master::DEFAULT_SYSTEM_PROMPT,
                   max_steps: 12, on_step: nil)
      @llm = llm
      @tools = tools
      @memory = memory
      @system_prompt = system_prompt
      @max_steps = max_steps
      @on_step = on_step # optional lambda(**info) for logging / UI updates
    end

    # Runs the loop until the model produces a final answer (or max_steps).
    # Returns the final assistant text.
    def run(user_message, thread_id: "default")
      memory.append(thread_id, role: "user", content: user_message)

      messages = [{ role: "system", content: @system_prompt }]
      messages.concat(memory.history(thread_id))

      (1..@max_steps).each do |step|
        message = llm.chat(messages, tools: tools.schemas)
        tool_calls = message["tool_calls"]

        if tool_calls.nil? || tool_calls.empty?
          answer = message["content"].to_s
          memory.append(thread_id, role: "assistant", content: answer)
          return answer
        end

        # Keep the assistant's tool-call turn, then append one result per call.
        messages << message
        tool_calls.each do |tc|
          name   = tc.dig("function", "name")
          args   = safe_parse_args(tc.dig("function", "arguments"))
          notify(step: step, type: :tool_call, name: name, args: args)

          result = tools.dispatch(name, args)
          notify(step: step, type: :tool_result, name: name, result: result)

          messages << {
            "role"         => "tool",
            "tool_call_id" => tc["id"],
            "content"      => JSON.generate(result)
          }
        end
      end

      raise MaxStepsExceeded, "no final answer after #{@max_steps} steps"
    end

    private

    def safe_parse_args(raw)
      JSON.parse(raw.to_s)
    rescue JSON::ParserError
      {}
    end

    def notify(**info)
      @on_step&.call(info)
    end
  end
end
