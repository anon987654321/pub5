# frozen_string_literal: true

require "faraday"
require "json"

module Master
  class LLMError < StandardError; end

  # Talks to any OpenAI-compatible /chat/completions endpoint:
  #   OpenAI, Ollama (/v1), LM Studio, vLLM, Groq, Together, ...
  # Swap base_url + model to move between hosted and local models without
  # touching any other code.
  class LLMAdapter
    def initialize(base_url:, api_key: "none", model:, temperature: 0.2, request_timeout: 120)
      @model = model
      @temperature = temperature
      @api_key = api_key
      @conn = Faraday.new(url: base_url) do |f|
        f.options.timeout = request_timeout
        f.options.open_timeout = 10
        f.response :json, content_type: /\bjson$/
        f.adapter :net_http
      end
    end

    # Returns the assistant message as a hash with string keys:
    #   { "role" => "assistant", "content" => "..." | nil,
    #     "tool_calls" => [ ... ] | nil }
    def chat(messages, tools: [])
      body = { model: @model, messages: messages, temperature: @temperature }
      body[:tools] = tools unless tools.empty?

      resp = @conn.post("chat/completions", body.to_json) do |req|
        req.headers["Content-Type"] = "application/json"
        req.headers["Authorization"] = "Bearer #{@api_key}"
      end

      if resp.status != 200
        raise LLMError, "LLM HTTP #{resp.status}: #{truncate(resp.body.to_s)}"
      end

      resp.body.dig("choices", 0, "message") ||
        raise(LLMError, "unexpected response shape: #{truncate(resp.body.to_s)}")
    end

    private

    def truncate(str, n = 300)
      str = str.to_s
      str.length > n ? "#{str[0, n]}..." : str
    end
  end
end
