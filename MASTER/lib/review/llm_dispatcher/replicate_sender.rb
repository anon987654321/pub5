# frozen_string_literal: true

require "json"
require "net/http"
require "timeout"
require "uri"
require_relative "../../trace/session"

module Master
  module Review
    class LLMDispatcher

      # Replicate's hosted language models, one POST away. This lane owns the
      # prediction poll loop and the per-family request shape; HttpSender keeps
      # the local-server and hosted OpenAI-compatible lanes. Both modules are
      # included into LLMDispatcher and neither owns the other.
      module ReplicateSender
        OPEN_TIMEOUT_S = 5
        REPLICATE_API = "https://api.replicate.com/v1"
        REPLICATE_WAIT_S = 60
        REPLICATE_MAX_POLLS = 240
        REPLICATE_POLL_TIMEOUT_S = 240
        REPLICATE_POLL_OPEN_TIMEOUT_S = 5
        REPLICATE_POLL_READ_TIMEOUT_S = 10
        REPLICATE_POLL_INTERVAL_S = 1

        # A poll URL is the exact API origin and a prediction path, nothing
        # else: no userinfo, port, query or fragment a redirect could steer.
        REPLICATE_POLL_URL = %r{\Ahttps://api\.replicate\.com/v1/predictions/[A-Za-z0-9_-]+\z}
        REPLICATE_MAX_TOKENS = 4096
        REPLICATE_BUDGET_LOCK = Mutex.new
        REPLICATE_BUDGET_STATE = { spent: 0.0 }

        # Each Replicate chat model declares its own spelling for the token cap
        # and the system prompt, and Replicate drops a key the model does not
        # declare rather than refusing it, so the wrong spelling is silently
        # lost: the OpenAI gpt-5.x/gpt-4.x models take max_completion_tokens
        # (max_tokens is ignored), the Gemini models take max_output_tokens and
        # system_instruction (system_prompt is ignored), and Anthropic and
        # gpt-oss take max_tokens with system_prompt. Chosen from the slug.
        REPLICATE_CHAT_SHAPES = {
          "openai/gpt-5" => { tokens: :max_completion_tokens, system: :system_prompt },
          "openai/gpt-4" => { tokens: :max_completion_tokens, system: :system_prompt },
          "google/" => { tokens: :max_output_tokens, system: :system_instruction },
        }.freeze
        REPLICATE_DEFAULT_CHAT_SHAPE = { tokens: :max_tokens, system: :system_prompt }.freeze

        private

        def replicate_chat_model?(model_id) = model_id.to_s.start_with?("replicate:")

        # Replicate answers inside the wait window or hands back a prediction to
        # poll; either way the output is the reply's tokens as an array.
        def send_replicate_chat(selected_model, messages, sys:)
          headers = replicate_headers
          return Result.err("replicate: missing API token", category: :no_api_key) unless headers

          slug = selected_model.delete_prefix("replicate:")
          reservation = reserve_replicate_chat_budget!(slug, messages:, sys:)
          return reservation if reservation.respond_to?(:err?) && reservation.err?

          input = replicate_chat_input(slug, messages:, sys:)
          response = post_json("#{REPLICATE_API}/models/#{slug}/predictions", { input: }, headers:,
                                                                                         timeout: REPLICATE_WAIT_S + 10)
          return http_lane_error("replicate", response) unless response.is_a?(Net::HTTPSuccess)

          result = replicate_output(JSON.parse(response.body), headers:)
          record_replicate_chat_usage(slug, messages:, sys:, response: result.value!) if result.ok?
          result
        rescue JSON::ParserError
          Result.err("replicate: invalid prediction response", category: :provider_error)
        end

        # Reserve the maximum billable completion plus a safety-adjusted input
        # estimate before the provider sees the request. The shared process
        # budget is intentionally conservative: a timeout after POST may still
        # have started a billable prediction, so failed/ambiguous calls keep it.
        def reserve_replicate_chat_budget!(slug, messages:, sys:)
          config = Master.models_config.fetch("replicate_chat_budget")
          rates = config.fetch("prices_usd_per_million").fetch(slug.to_s)
          input_text = [text_prompt_for(messages), sys.to_s].reject(&:empty?).join("\n")
          input_tokens = Master::Trace::Session.estimate_tokens(input_text)
          safety = Float(config.fetch("input_token_safety_factor"))
          estimate = (
            (input_tokens * safety * Float(rates.fetch("input"))) +
            (REPLICATE_MAX_TOKENS * Float(rates.fetch("output")))
          ) / 1_000_000.0
          call_cap = replicate_budget_limit(config.fetch("call_cap_usd"), "MASTER_REPLICATE_CALL_CAP_USD")
          run_cap = replicate_budget_limit(config.fetch("run_cap_usd"), "MASTER_REPLICATE_BUDGET_USD")
          return Result.err(format("replicate: estimated call $%.4f exceeds $%.2f call cap", estimate, call_cap),
                            category: :budget) if estimate > call_cap

          REPLICATE_BUDGET_LOCK.synchronize do
            spent = REPLICATE_BUDGET_STATE.fetch(:spent)
            if spent + estimate > run_cap
              return Result.err(format("replicate: estimated call $%.4f exceeds $%.2f remaining run budget",
                                       estimate, run_cap - spent), category: :budget)
            end
            REPLICATE_BUDGET_STATE[:spent] = spent + estimate
          end
          estimate
        rescue KeyError, ArgumentError, TypeError => e
          Result.err("replicate: spend preflight refused the call (#{e.class})", category: :budget)
        end

        def replicate_budget_limit(configured, env_name)
          ceiling = Float(configured)
          override = ENV[env_name].to_s.strip
          return ceiling if override.empty?

          requested = Float(override)
          raise ArgumentError, "#{env_name} must be positive and finite" unless requested.positive? && requested.finite?

          [ceiling, requested].min
        end

        def replicate_chat_spent
          REPLICATE_BUDGET_LOCK.synchronize { REPLICATE_BUDGET_STATE.fetch(:spent) }
        end

        def reset_replicate_chat_budget!
          REPLICATE_BUDGET_LOCK.synchronize { REPLICATE_BUDGET_STATE[:spent] = 0.0 }
        end

        # The reservation is the safety ceiling; the ledger records an estimate
        # based on the actual returned text and is explicitly marked approximate.
        def record_replicate_chat_usage(slug, messages:, sys:, response:)
          return unless @session&.respond_to?(:record_cost)

          rates = Master.models_config.fetch("replicate_chat_budget")
            .fetch("prices_usd_per_million").fetch(slug.to_s)
          input_tokens = Master::Trace::Session.estimate_tokens(
            [text_prompt_for(messages), sys.to_s].reject(&:empty?).join("\n")
          )
          output_tokens = Master::Trace::Session.estimate_tokens(response.to_s)
          cost = ((input_tokens * Float(rates.fetch("input"))) +
                  (output_tokens * Float(rates.fetch("output")))) / 1_000_000.0
          total = input_tokens + output_tokens
          model = "replicate:#{slug}"
          @session.record_cost(cost, model:, tokens: total, approximate: true)
          publish_llm_cost(model:, cost:, tokens: total, tokens_in: input_tokens,
                           tokens_out: output_tokens, estimated: true, approximate: true) if
            respond_to?(:publish_llm_cost, true)
        rescue StandardError => e
          @bus&.publish("cost:record_error", error_class: e.class.name,
                        **Master::Execution::Contract.diagnostic_fields(e.message))
        end

        # The token-cap and system-prompt key names this model declares, by slug
        # family; a model that declares neither keeps the Replicate default.
        def replicate_chat_shape(slug)
          REPLICATE_CHAT_SHAPES.each do |prefix, shape|
            return shape if slug.to_s.start_with?(prefix)
          end
          REPLICATE_DEFAULT_CHAT_SHAPE
        end

        # The request body for one chat model, keyed the way its family declares.
        def replicate_chat_input(slug, messages:, sys:)
          shape = replicate_chat_shape(slug)
          input = { prompt: text_prompt_for(messages), shape[:tokens] => REPLICATE_MAX_TOKENS }
          input[shape[:system]] = sys unless sys.to_s.empty?
          input
        end

        def replicate_output(prediction, headers:)
          deadline = monotonic_now + REPLICATE_POLL_TIMEOUT_S
          REPLICATE_MAX_POLLS.times do
            settled = settled_prediction(prediction)
            return settled if settled

            remaining = deadline - monotonic_now
            return Result.err("replicate: polling deadline exceeded", category: :timeout) unless remaining.positive?

            sleep([REPLICATE_POLL_INTERVAL_S, remaining].min)
            prediction = fetch_replicate_prediction(prediction, headers:, deadline:)
            return prediction if prediction.is_a?(Result)
          end
          Result.err("replicate: no answer after #{REPLICATE_MAX_POLLS} polls", category: :timeout)
        end

        # A prediction that has stopped changing: succeeded yields its tokens,
        # failed and canceled yield the error, anything else is nil so the
        # caller keeps polling.
        def settled_prediction(prediction)
          unless prediction.is_a?(Hash)
            return Result.err("replicate: invalid prediction response", category: :provider_error)
          end
          return Result.ok(Array(prediction["output"]).join) if prediction["status"] == "succeeded"
          return unless %w[failed canceled].include?(prediction["status"])

          Result.err("replicate: #{prediction['error'] || prediction['status']}", category: :provider_error)
        end

        def fetch_replicate_prediction(prediction, headers:, deadline:)
          uri = replicate_poll_uri(prediction)
          remaining = deadline - monotonic_now
          return Result.err("replicate: polling deadline exceeded", category: :timeout) unless remaining.positive?

          response = replicate_poll_request(uri, headers, remaining:)
          return http_lane_error("replicate", response) unless response.is_a?(Net::HTTPSuccess)

          parsed = JSON.parse(response.body)
          return parsed if parsed.is_a?(Hash)

          Result.err("replicate: polling response was not an object", category: :provider_error)
        rescue ArgumentError, TypeError, URI::InvalidURIError
          Result.err("replicate: refused an invalid polling endpoint", category: :policy)
        rescue Net::OpenTimeout, Net::ReadTimeout, Timeout::Error
          Result.err("replicate: polling request timed out", category: :timeout)
        rescue JSON::ParserError
          Result.err("replicate: invalid polling response", category: :provider_error)
        end

        def replicate_poll_request(uri, headers, remaining:)
          request = Net::HTTP::Get.new(uri.request_uri, headers)
          Net::HTTP.start(
            uri.host, uri.port, use_ssl: true,
            open_timeout: [REPLICATE_POLL_OPEN_TIMEOUT_S, remaining].min,
            read_timeout: [REPLICATE_POLL_READ_TIMEOUT_S, remaining].min,
          ) { |http| http.request(request) }
        end

        # A poll URL is trusted only when it is exactly the API origin and a
        # prediction path: URI.parse accepts userinfo, a non-default port, a
        # query or a fragment, each of which could carry a request elsewhere,
        # so the whole string is matched rather than its parsed parts.
        def replicate_poll_uri(prediction)
          urls = prediction["urls"]
          value = urls.is_a?(Hash) ? urls["get"].to_s : ""
          raise ArgumentError, "poll URL is outside the Replicate API" unless value.match?(REPLICATE_POLL_URL)

          URI.parse(value)
        end

        def replicate_headers
          token = [ENV["REPLICATE_API_TOKEN"], ENV["REPLICATE_API_KEY"]]
            .map { |key| key.to_s.strip }.find { |key| !key.empty? }
          return if token.to_s.empty?

          { "Authorization" => "Bearer #{token}", "Prefer" => "wait=#{REPLICATE_WAIT_S}" }
        end

        def monotonic_now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        def post_json(url, body, headers: {}, timeout: REPLICATE_WAIT_S + 10)
          uri = URI(url)
          request = Net::HTTP::Post.new(uri.request_uri, headers.merge("Content-Type" => "application/json"))
          request.body = JSON.generate(body)
          Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                          open_timeout: OPEN_TIMEOUT_S, read_timeout: timeout) do |http|
            http.request(request)
          end
        end
      end
    end
  end
end
