# frozen_string_literal: true

module Core
  # The one model client. Every call goes through here so every call lands in
  # the ledger with its tokens and cost, and a run's budget is checked before
  # the call rather than discovered after. Providers come from
  # registry/models.yml; a provider without a `protocol` is reached some other
  # way (a CLI lane) and this client refuses it.
  class LLM
    Answer = Data.define(:text, :tokens_in, :tokens_out, :cost_usd, :model)

    PROTOCOLS = {
      "anthropic" => {
        path: "/messages",
        headers: ->(key) { { "x-api-key" => key, "anthropic-version" => "2023-06-01" } },
        body: lambda { |model, messages, system, max|
          { model:, max_tokens: max, messages:, system: }.compact
        },
        read: lambda { |j|
          [j.fetch("content").filter_map { |c| c["text"] }.join, j.dig("usage", "input_tokens"), j.dig("usage", "output_tokens")]
        }
      },
      "openai" => {
        path: "/chat/completions",
        headers: ->(key) { { "authorization" => "Bearer #{key}" } },
        body: lambda { |model, messages, system, max|
          { model:, max_tokens: max, messages: (system ? [{ role: "system", content: system }] : []) + messages }
        },
        read: lambda { |j|
          [j.dig("choices", 0, "message", "content").to_s, j.dig("usage", "prompt_tokens"), j.dig("usage", "completion_tokens")]
        }
      }
    }.freeze

    def initialize(models:, knobs:, ledger:, transport: HTTP)
      @models = models
      @knobs = knobs
      @ledger = ledger
      @transport = transport
    end

    def complete(provider:, model:, messages:, system: nil, max_tokens: 1024)
      row = @models.fetch("providers").fetch(provider.to_s) { raise Refusal.new(:llm, provider, "unknown provider") }
      protocol = PROTOCOLS.fetch(row["protocol"].to_s) { raise Refusal.new(:llm, provider, "no HTTP protocol declared") }
      refuse_offline!(provider)
      refuse_over_budget!(provider)
      key = @knobs.first(row.fetch("env", []))
      raise Refusal.new(:llm, provider, "no key set in #{row.fetch('env', []).join(' or ')}") unless key

      reply = @transport.request(:post, "#{row.fetch('base')}#{protocol[:path]}",
                                 headers: protocol[:headers].call(key),
                                 body: protocol[:body].call(model, messages, system, max_tokens),
                                 timeout: @knobs.fetch("PUB5_HTTP_TIMEOUT"))
      record(provider, model, reply, protocol)
    end

    private

    def record(provider, model, reply, protocol)
      unless reply.ok?
        @ledger.append(:llm, provider:, model:, status: reply.status, tokens_in: 0, tokens_out: 0, cost_usd: 0.0)
        raise Refusal.new(:llm, provider, "HTTP #{reply.status}")
      end

      text, tokens_in, tokens_out = protocol[:read].call(reply.json)
      cost = cost_usd(model, tokens_in.to_i, tokens_out.to_i)
      @ledger.append(:llm, provider:, model:, status: reply.status, tokens_in:, tokens_out:, cost_usd: cost)
      Answer.new(text:, tokens_in:, tokens_out:, cost_usd: cost, model:)
    end

    # nil when the model has no price in the registry: unmeasured, not free.
    def cost_usd(model, tokens_in, tokens_out)
      price = @models.fetch("prices", {})[model] or return nil
      ((tokens_in * price.fetch("prompt_usd_per_m")) + (tokens_out * price.fetch("completion_usd_per_m"))) / 1_000_000.0
    end

    def refuse_offline!(provider)
      raise Refusal.new(:llm, provider, "PUB5_OFFLINE is set") if @knobs.fetch("PUB5_OFFLINE")
    end

    def refuse_over_budget!(provider)
      budget = @knobs.fetch("PUB5_RUN_BUDGET_USD")
      spent = @ledger.spend.fetch("cost_usd")
      raise Refusal.new(:llm, provider, "run budget #{budget} USD spent (#{spent})") if budget && spent >= budget
    end
  end
end
