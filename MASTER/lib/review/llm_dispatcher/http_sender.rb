# frozen_string_literal: true

require "json"
require "net/http"
require "timeout"
require "uri"
require_relative "../../io/provider_concurrency"

module Master
  module Review
    class LLMDispatcher
      # Two lanes RubyLLM has no provider for, each one POST away: an
      # OpenAI-compatible server on this machine (mistral.rs, LM Studio,
      # llama-server) and Replicate's hosted language models.
      #
      # The lane's own deadlines are split: a short handshake budget (a lane
      # whose connect or TLS phase is dead never gets past it, and the failure
      # falls through to the circuit breaker as a provider failure) and a
      # read-idle budget (each silent socket read must die on its own; a body
      # that keeps delivering never trips it, so a token arriving every few
      # seconds reads for as long as the provider writes).
      module HttpSender
        LOCAL_SERVER_TIMEOUT_S = 300
        OPEN_TIMEOUT_S = 5
        READ_IDLE_TIMEOUT_S = 60

        private

        # Tests substitute their own idle budget; no operator surface.
        def read_idle_timeout_s = READ_IDLE_TIMEOUT_S
        REPLICATE_API = "https://api.replicate.com/v1"
        REPLICATE_WAIT_S = 60
        REPLICATE_MAX_POLLS = 240
        REPLICATE_POLL_TIMEOUT_S = 240
        REPLICATE_POLL_OPEN_TIMEOUT_S = 5
        REPLICATE_POLL_READ_TIMEOUT_S = 10
        REPLICATE_POLL_INTERVAL_S = 1
        REPLICATE_API_HOST = "api.replicate.com"
        REPLICATE_MAX_TOKENS = 4096

        # Tests substitute their own idle budget; no operator surface.
        def read_idle_timeout_s = READ_IDLE_TIMEOUT_S

        private

        def local_server_model?(model_id) = model_id.to_s.start_with?("local:")

        def replicate_chat_model?(model_id) = model_id.to_s.start_with?("replicate:")

        # The router found which server listed the model; the call goes there.
        def send_local_server(selected_model, messages, sys:, temperature: nil)
          base = @model_router&.local_server_for(selected_model)
          return Result.err("no local server lists #{selected_model}", category: :model_missing) unless base

          messages = fit_to_window(selected_model, messages)
          openai_chat(base, selected_model.delete_prefix("local:"), messages, sys:, temperature:, lane: "local server")
        end

        # Context-safe degradation: compact the history to the target's window
        # before the POST. Master.context_window answers the configured or
        # registry window and falls back to the 128k default, so a lane whose
        # window is genuinely unknown compacts only a truly enormous history,
        # while a small local bed compacts at its real one.
        def fit_to_window(selected_model, messages)
          Master::CLI::Routing::ModelRouter::ContextBudget.fit(messages, Master.context_window(selected_model))
        end

        def refuses_sensitive?(endpoint, sensitivity)
          !Master::CLI::Routing::ModelRouter::PrivacyPosture.allows?(hosted_posture(endpoint), sensitivity)
        end

        def hosted_posture(endpoint)
          endpoint[:posture] || Master::CLI::Routing::ModelRouter::PrivacyPosture::UNKNOWN
        end

        # A hosted OpenAI-compatible endpoint the router listed in models.yml
        # openai_compatible; the key rides along only when one is set.
        def hosted_lane?(model_id) = !@model_router&.hosted_endpoint_for(model_id).nil?

        def send_hosted(selected_model, messages, sys:, temperature: nil, sensitivity: :normal)
          endpoint = @model_router.hosted_endpoint_for(selected_model)
          name, model = selected_model.split(":", 2)
          # A request tagged :sensitive rides only lanes whose declared
          # privacy posture allows it (ModelRouter::PrivacyPosture — the
          # local bed is the one `anonymous` lane today). Unknown refuses:
          # "nobody wrote the policy down" is not consent.
          if refuses_sensitive?(endpoint, sensitivity)
            return Result.err(
              "#{name}: privacy posture #{hosted_posture(endpoint)} refuses :sensitive dispatch",
              category: :privacy,
            )
          end
          # FreeOnly is a send-boundary guarantee, not just a discovery rule.
          # HostedEndpoints drops configured keys when building its anonymous
          # index, but KeyRotator resolves keys at call time; without this gate
          # an endpoint with key_env values could silently turn the "free" lane
          # back into a keyed request.
          key = if ENV["MASTER_FREE_ONLY"].to_s != ""
                  nil
                else
                  Io::KeyRotator.active_key_for(name) || endpoint[:key]
                end
          headers = key ? { "Authorization" => "Bearer #{key}" } : {}
          messages = fit_to_window(selected_model, messages)
          request = lambda do
            openai_chat(endpoint[:base], model, messages, sys:, temperature:, headers:,
                        lane: name, fold_system: endpoint[:fold_system] == true)
          end
          return request.call unless endpoint[:max_concurrency]

          Io::ProviderConcurrency.with_slot(
            bucket: endpoint[:quota_bucket] || name,
            limit: endpoint[:max_concurrency],
            wait_seconds: endpoint.fetch(:concurrency_wait_seconds, 15),
          ) { request.call }
        rescue Io::ProviderConcurrency::Saturated
          Result.err("#{name}: concurrency budget is saturated; trying the next lane", category: :timeout)
        end

        # The gateway cap is on the system role only (the agent server refuses a
        # system turn over 32 KiB but accepts the same text as a user turn). A
        # system turn that would be refused is delivered as a leading user turn
        # instead, so the lane carries the constitution it could not otherwise.
        def fold_long_system(rows, limit: 32_768)
          head = rows.first
          return rows unless head.is_a?(Hash) && head[:role].to_s == "system"
          return rows if head[:content].to_s.bytesize <= limit

          [{ role: "user", content: head[:content].to_s }] + rows.drop(1)
        end

        def openai_chat(base, model, messages, sys:, temperature:, lane:, headers: {}, fold_system: false)
          rows = ollama_messages(messages, sys)
          rows = fold_long_system(rows) if fold_system
          body = { model:, messages: rows, stream: true }
          body[:temperature] = temperature if temperature
          request = Net::HTTP::Post.new(URI("#{base.chomp('/')}/chat/completions").request_uri,
                                        headers.merge("Content-Type" => "application/json"))
          request.body = JSON.generate(body)
          reply = read_streaming_lane(base, request, lane)
          return reply if reply.is_a?(Result)

          Result.ok(reply)
        rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, SocketError => e
          Result.err("#{lane} unreachable at #{base}: #{e.message}", category: :provider_error)
        end

        # One lane call with its deadlines split: a short handshake budget
        # (connect plus TLS) and a read-idle budget that every silent socket
        # read must meet. The socket stays open while the body assembles, so
        # an answer that keeps delivering reads to the end however long that
        # takes; one that goes silent dies at the idle budget, not sooner.
        # A dead handshake raises and falls through to the circuit breaker's
        # failure accounting.
        def read_streaming_lane(base, request, lane)
          uri = URI("#{base.chomp('/')}/chat/completions")
          Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                          open_timeout: OPEN_TIMEOUT_S, read_timeout: read_idle_timeout_s) do |http|
            # The block form is the only one that leaves the body unread. A
            # block-less request returns a response whose body net/http has
            # already consumed, and read_body on it raises "called twice" —
            # which every streaming provider answered with, so the whole
            # event-stream path failed as a provider error instead of parsing.
            # http.request returns the response rather than the block's value,
            # so the answer is carried out in a local.
            answer = nil
            http.request(request) do |response|
              return http_lane_error(lane, response) unless response.is_a?(Net::HTTPSuccess)

              answer = if response["Content-Type"].to_s.include?("event-stream")
                         assemble_stream(response, lane)
                       else
                         JSON.parse(response.body).dig("choices", 0, "message", "content").to_s
                       end
            end
            answer
          end
        rescue Net::ReadTimeout => e
          Result.err("#{lane} went silent longer than #{READ_IDLE_TIMEOUT_S}s: #{e.message}", category: :timeout)
        end

        # SSE deltas as they arrive. An event is the fields up to the next blank
        # line, and the `event:` field names it; a `data:` line that follows
        # `event: ping` is the ping's payload, not the next chat token, so the
        # name has to be carried until the dispatch rather than ignored. Only
        # the unnamed (default `message`) events are the answer.
        def assemble_stream(response, lane)
          content = +""
          tail = +""
          event = nil
          response.read_body do |chunk|
            tail << chunk
            while (index = tail.index("\n"))
              (line, tail = tail[0...index], tail[(index + 1)..].to_s)
              field, _, value = line.strip.partition(":")
              case field
              when "event" then event = value.strip
              when "data"
                payload = value.strip
                next if payload.empty? || payload == "[DONE]"
                next unless event.nil? || event == "message"

                delta = JSON.parse(payload).dig("choices", 0, "delta", "content")
                content << delta if delta.is_a?(String)
              when "" then event = nil # the blank line ends the event
              end
            end
          end
          content
        rescue JSON::ParserError => e
          Result.err("#{lane} sent a malformed stream: #{e.message}", category: :provider_error)
        end

        # Replicate answers inside the wait window or hands back a prediction to
        # poll; either way the output is the reply's tokens as an array.
        def send_replicate_chat(selected_model, messages, sys:)
          headers = replicate_headers
          return Result.err("replicate: missing API token", category: :no_api_key) unless headers

          slug = selected_model.delete_prefix("replicate:")
          input = { prompt: text_prompt_for(messages), max_tokens: REPLICATE_MAX_TOKENS }
          input[:system_prompt] = sys unless sys.to_s.empty?
          response = post_json("#{REPLICATE_API}/models/#{slug}/predictions", { input: }, headers:,
                                                                                         timeout: REPLICATE_WAIT_S + 10)
          return http_lane_error("replicate", response) unless response.is_a?(Net::HTTPSuccess)

          replicate_output(JSON.parse(response.body), headers:)
        rescue JSON::ParserError
          Result.err("replicate: invalid prediction response", category: :provider_error)
        end

        def replicate_output(prediction, headers:)
          deadline = monotonic_now + REPLICATE_POLL_TIMEOUT_S
          REPLICATE_MAX_POLLS.times do
            unless prediction.is_a?(Hash)
              return Result.err("replicate: invalid prediction response", category: :provider_error)
            end
            return Result.ok(Array(prediction["output"]).join) if prediction["status"] == "succeeded"
            if %w[failed canceled].include?(prediction["status"])
              return Result.err("replicate: #{prediction['error'] || prediction['status']}", category: :provider_error)
            end

            remaining = deadline - monotonic_now
            return Result.err("replicate: polling deadline exceeded", category: :timeout) unless remaining.positive?

            sleep([REPLICATE_POLL_INTERVAL_S, remaining].min)
            prediction = fetch_replicate_prediction(prediction, headers:, deadline:)
            return prediction if prediction.is_a?(Result)
          end
          Result.err("replicate: no answer after #{REPLICATE_MAX_POLLS} polls", category: :timeout)
        end

        def fetch_replicate_prediction(prediction, headers:, deadline:)
          uri = replicate_poll_uri(prediction)
          remaining = deadline - monotonic_now
          return Result.err("replicate: polling deadline exceeded", category: :timeout) unless remaining.positive?

          request = Net::HTTP::Get.new(uri.request_uri, headers)
          response = Net::HTTP.start(
            uri.host, uri.port, use_ssl: true,
            open_timeout: [REPLICATE_POLL_OPEN_TIMEOUT_S, remaining].min,
            read_timeout: [REPLICATE_POLL_READ_TIMEOUT_S, remaining].min,
          ) { |http| http.request(request) }
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

        def replicate_poll_uri(prediction)
          urls = prediction["urls"]
          value = urls.is_a?(Hash) ? urls["get"].to_s : ""
          uri = URI.parse(value)
          allowed_path = %r{\A/v1/predictions/[A-Za-z0-9_-]+\z}
          allowed = uri.is_a?(URI::HTTPS) && uri.host == REPLICATE_API_HOST && uri.port == 443 &&
                    uri.userinfo.nil? && uri.query.nil? && uri.fragment.nil? && uri.path.match?(allowed_path)
          raise ArgumentError, "poll URL is outside the Replicate API" unless allowed

          uri
        end

        def replicate_headers
          token = [ENV["REPLICATE_API_TOKEN"], ENV["REPLICATE_API_KEY"]]
            .map { |key| key.to_s.strip }.find { |key| !key.empty? }
          return if token.to_s.empty?

          { "Authorization" => "Bearer #{token}", "Prefer" => "wait=#{REPLICATE_WAIT_S}" }
        end

        def monotonic_now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        def post_json(url, body, headers: {}, timeout: LOCAL_SERVER_TIMEOUT_S)
          uri = URI(url)
          request = Net::HTTP::Post.new(uri.request_uri, headers.merge("Content-Type" => "application/json"))
          request.body = JSON.generate(body)
          Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                          open_timeout: OPEN_TIMEOUT_S, read_timeout: timeout) do |http|
            http.request(request)
          end
        end

        # A refused key, a spent balance and a busy host are three different
        # moves for the chain, so each gets the category that makes it.
        def http_lane_error(lane, response)
          said = "#{lane} #{response.code}: #{response.body.to_s[0, 300]}"
          retry_after = response.get_fields("Retry-After")&.first if response.respond_to?(:get_fields)
          # Preserve numeric provider cooldown hints in the diagnostic passed to
          # LaneReply/LaneQuota. Ignore HTTP-date values here; never guess a
          # reset interval from an arbitrary date string.
          said += " Retry-After: #{retry_after}" if response.code == "429" && retry_after.to_s.match?(/\A\d+\z/)
          category = { "401" => :no_api_key, "402" => :budget, "404" => :model_missing, "429" => :rate_limit }
                     .fetch(response.code) { response.code.start_with?("4") ? :validation : :provider_error }
          Result.err(said, category:)
        end
      end
    end
  end
end
