# frozen_string_literal: true

require "json"

module Master
  module CLI
    module Routing
      class ModelRouter
        # Hosted OpenAI-compatible endpoints, models.yml `openai_compatible`:
        # each lists its models at <base>/models, and they become
        # "<name>:<model>" lanes. With none of its key_env set, an endpoint
        # offers only the models its `keyless` rule selects: fields matched
        # against the listing (`tier`, `isFree`, ...) or an explicit `allow`
        # list of ids when the listing cannot self-describe (OVH). LLM7 answers
        # GLM-5.3-Flash without a key and refuses gpt-5.5 with a 401, and the
        # listing says which is which.
        module HostedEndpoints
          HOSTED_TIMEOUT_S = 5
          def hosted_models = hosted_index.keys

          # { base:, key: } for a hosted lane id; nil when no endpoint lists it.
          def hosted_endpoint_for(model_id) = hosted_index[model_id.to_s]

          # The lane's declared privacy posture for :sensitive dispatch
          # decisions (ModelRouter::PrivacyPosture); unknown when no endpoint
          # lists the id.
          def hosted_posture_for(model_id)
            hosted_endpoint_for(model_id)&.fetch(:posture, nil) || PrivacyPosture::UNKNOWN
          end

          def hosted_model?(model_id) = hosted_endpoints.key?(model_id.to_s.split(":", 2).first)

          private

          # A local OpenAI-compatible gateway is optional and deliberately opt-in.
          # Set MASTER_LLM_GATEWAY_URL to its /v1 base; the endpoint is then
          # discovered and routed through the same health/fallback chain as the
          # catalogued providers. No extra Ruby routing gem is required.
          def hosted_endpoints
            configured = @rules.fetch("openai_compatible", {}) || {}
            base = ENV["MASTER_LLM_GATEWAY_URL"].to_s.strip
            return configured if base.empty?

            configured.merge("gateway" => gateway_spec(base))
          rescue URI::Error, ArgumentError => e
            Master::Ground::Swallow.log(e, context: "model_router.gateway_config")
            configured || {}
          end

          def gateway_spec(base)
            uri = URI.parse(base)
            unless uri.is_a?(URI::HTTP) && !uri.host.to_s.empty?
              raise ArgumentError, "MASTER_LLM_GATEWAY_URL must be an absolute HTTP(S) URL"
            end
            if uri.userinfo || uri.query || uri.fragment
              raise ArgumentError, "MASTER_LLM_GATEWAY_URL must not include credentials, query or fragment"
            end
            if uri.scheme == "http" && !loopback_gateway_host?(uri.host)
              raise ArgumentError, "unencrypted remote gateway refused; use loopback HTTP or HTTPS"
            end

            spec = {
              "base" => base.chomp("/"),
              "key_env" => %w[MASTER_LLM_GATEWAY_KEY FREELLMPOOL_PROXY_KEY],
              "keyless" => {},
            }
            # A gateway that caps the system turn (the local agent server refuses
            # a system message over 32 KiB, then accepts the same text as a user
            # turn) cannot carry MASTER's constitution in a system role. When
            # MASTER_LLM_GATEWAY_FOLD_SYSTEM is set, the dispatcher folds an
            # over-limit system prompt into a leading user turn for this lane.
            spec["fold_system"] = true if fold_system_requested?
            spec
          end

          def loopback_gateway_host?(host)
            %w[localhost 127.0.0.1 ::1 [::1]].include?(host.to_s.downcase)
          end

          def fold_system_requested? = ENV["MASTER_LLM_GATEWAY_FOLD_SYSTEM"].to_s != ""

          def hosted_index
            return {} if ENV["MASTER_NO_POOL_PROBES"] == "1"

            @hosted_index ||= hosted_endpoints.each_with_object({}) do |(name, spec), index|
              key = hosted_key(spec)
              # MASTER_FREE_ONLY asks no lane that needs a key: the key is
              # dropped, so an endpoint serves its keyless rule or nothing at
              # all. MASTER_NO_KEYLESS is the mirror: the anonymous tier is
              # refused outright, so an endpoint with no key offers nothing
              # until one is set.
              key = nil if free_only?
              next if key.nil? && (no_keyless? || !spec.key?("keyless"))

              endpoint = {
                base: spec["base"],
                key:,
                quota_bucket: (spec["quota_bucket"] || name).to_s,
                posture: PrivacyPosture.parse(spec["privacy_posture"]),
              }
              endpoint[:fold_system] = true if spec["fold_system"]
              concurrency_key = if key.nil? && spec.key?("keyless_max_concurrency")
                                   "keyless_max_concurrency"
                                 else
                                   "max_concurrency"
                                 end
              if spec.key?(concurrency_key)
                endpoint[:max_concurrency] = Integer(spec.fetch(concurrency_key))
                raise ArgumentError, "openai_compatible.#{name}.#{concurrency_key} must be positive" unless endpoint[:max_concurrency].positive?
                endpoint[:concurrency_wait_seconds] = Float(spec.fetch("concurrency_wait_seconds", 15))
                raise ArgumentError, "openai_compatible.#{name}.concurrency_wait_seconds cannot be negative" if endpoint[:concurrency_wait_seconds].negative?
              end
              hosted_ids(spec, key).each { |id| index["#{name}:#{id}"] ||= endpoint }
            end
          end

          def hosted_key(spec)
            Array(spec["key_env"]).map { |env| ENV[env].to_s }.find { |value| !value.empty? }
          end

          def free_only? = ENV["MASTER_FREE_ONLY"].to_s != ""

          def no_keyless? = ENV["MASTER_NO_KEYLESS"].to_s != ""

          def hosted_ids(spec, key)
            # The listing is fetched live on every index build; CatalogCache
            # keeps the last non-empty answer per (endpoint, mode) so an
            # offline start degrades to the previous catalogue instead of an
            # empty pool. Cached rows are already-filtered ids — the keyless
            # rule ran on the live rows — so the cache can never widen what
            # the rule admits.
            CatalogCache.ids_for(spec["base"], key ? "keyed" : "keyless") do
              live_hosted_ids(spec, key)
            end
          rescue StandardError => e
            Master::Ground::Swallow.log(e, context: "model_router.hosted", endpoint: spec["base"])
            []
          end

          def live_hosted_ids(spec, key)
            headers = key ? { "Authorization" => "Bearer #{key}" } : {}
            body = get_json("#{spec["base"].chomp("/")}/models", headers:, timeout: HOSTED_TIMEOUT_S)
            parsed = JSON.parse(body.to_s)
            # The OpenAI convention is {"data": [...]} of id-keyed rows; some
            # endpoints (Pollinations) answer a bare array of name-keyed rows
            # instead. Parse both shapes: indexing a bare array with ["data"]
            # raises TypeError, and the rescue below would then silently empty
            # the lane on a 200 response.
            rows = (parsed.is_a?(Hash) ? Array(parsed["data"]) : Array(parsed))
                   .select { |row| row.is_a?(Hash) && row.fetch("model_type", "chat") == "chat" }
            unless key
              keyless = spec["keyless"].is_a?(Hash) ? spec["keyless"] : {}
              # `allow` names the keyless model ids outright, for endpoints whose
              # listing cannot self-describe what a keyless key opens (OVH lists
              # its whisper/TTS/image rows beside the chat models it serves).
              allow = Array(keyless["allow"]).map(&:to_s)
              rules = keyless.reject { |field, _| field == "allow" }
              rows = rows.select do |row|
                id = row["id"] || row["name"]
                (allow.empty? || allow.include?(id.to_s)) &&
                  rules.all? { |field, want| row[field] == want }
              end
            end
            rows.filter_map { |row| row["id"] || row["name"] }
            # No rescue here: a failed or unparseable listing must reach
            # CatalogCache.ids_for (cached last-known-good) and then
            # hosted_ids's rescue. A rescue inside this method would answer []
            # before the cache is ever consulted, and the offline floor would
            # be dead the moment the network is.
          end
        end
      end
    end
  end
end
