# frozen_string_literal: true

module Master
  # Validates the nested provider-lane and media-lane catalogues inside models.yml.
  # Kept separate from tier identity/routing so each schema has one responsibility.
  module ModelCatalogueSectionsGuard
    module_function

    def validate(data, tiers:, errors:)
      validate_routing_and_policy(data, tiers, errors)
      validate_continuity(data, errors)
      validate_openrouter(data, errors)
      validate_ferrum_web_chat(data, errors)
      validate_mirror_redundancy(data, errors)
      validate_cli_lanes(data, errors)
      validate_openai_compatible(data, errors)
      validate_ollama(data, errors)
      validate_free_and_paid_tiers(data, errors)
      validate_media_lanes(data, errors)
    end

    def validate_routing_and_policy(data, tiers, errors)
      strict_fields(data["routing"], %w[enabled strategy escalation_enabled escalation_tier provider],
                    "models.yml routing", errors)
      routing_config = data["routing"].is_a?(Hash) ? data["routing"] : {}
      unless tiers.key?(routing_config["escalation_tier"])
        errors << "models.yml routing.escalation_tier must reference a declared model tier"
      end
      strict_fields(data["fallback_policy"], ["on"], "models.yml fallback_policy", errors)
      strict_fields(data["failover"],
                    %w[sequence cooldown_seconds cooldown_tiers skip_ttl_ms transient_skip_ttl_ms max_retries],
                    "models.yml failover", errors)
      strict_fields(data["defaults"], ["score"], "models.yml defaults", errors)
    end

    def validate_continuity(data, errors)
      strict_fields(data["continuity"], %w[enabled updated_at], "models.yml continuity", errors)
      continuity = data["continuity"].is_a?(Hash) ? data["continuity"] : {}
      errors << "models.yml continuity.enabled must be boolean" unless [true, false].include?(continuity["enabled"])
      errors << "models.yml continuity.updated_at must be non-empty text" unless
        continuity["updated_at"].is_a?(String) && !continuity["updated_at"].strip.empty?
    end

    def validate_openrouter(data, errors)
      strict_fields(data["openrouter"], %w[use_live_catalog daily_quota_per_model keys_env free_latest],
                    "models.yml openrouter", errors)
      openrouter = data["openrouter"].is_a?(Hash) ? data["openrouter"] : {}
      errors << "models.yml openrouter.use_live_catalog must be boolean" unless [true, false].include?(openrouter["use_live_catalog"])
      errors << "models.yml openrouter.daily_quota_per_model must be a positive integer" unless
        openrouter["daily_quota_per_model"].is_a?(Integer) && openrouter["daily_quota_per_model"].positive?
      validate_string_list(openrouter["keys_env"], "models.yml openrouter.keys_env", errors, nonempty: true)
      validate_string_list(openrouter["free_latest"], "models.yml openrouter.free_latest", errors, nonempty: true)
    end

    def validate_ferrum_web_chat(data, errors)
      strict_fields(data["ferrum_web_chat"],
                    %w[enabled_when_env auto_when_keyless profile_dir free_latest providers],
                    "models.yml ferrum_web_chat", errors)
      ferrum = data["ferrum_web_chat"].is_a?(Hash) ? data["ferrum_web_chat"] : {}
      %w[enabled_when_env profile_dir].each do |field|
        errors << "models.yml ferrum_web_chat.#{field} must be non-empty text" unless
          ferrum[field].is_a?(String) && !ferrum[field].strip.empty?
      end
      errors << "models.yml ferrum_web_chat.auto_when_keyless must be boolean" unless
        [true, false].include?(ferrum["auto_when_keyless"])
      validate_string_list(ferrum["free_latest"], "models.yml ferrum_web_chat.free_latest", errors, nonempty: true)
      providers = ferrum["providers"].is_a?(Hash) ? ferrum["providers"] : {}
      providers.each { |name, row| validate_ferrum_provider(name, row, errors) }
      errors << "models.yml ferrum_web_chat.providers must not be empty" if providers.empty?
    end

    def validate_ferrum_provider(name, row, errors)
      label = "models.yml ferrum_web_chat.providers.#{name}"
      strict_fields(row, %w[url input_selector reply_selector timeout], label, errors)
      return unless row.is_a?(Hash)

      %w[url input_selector reply_selector].each do |field|
        errors << "#{label}.#{field} must be non-empty text" unless
          row[field].is_a?(String) && !row[field].strip.empty?
      end
      errors << "#{label}.timeout must be positive" unless row["timeout"].is_a?(Numeric) && row["timeout"].positive?
    end

    def validate_mirror_redundancy(data, errors)
      strict_fields(data["three_mirror_redundancy"], %w[pool quorum], "models.yml three_mirror_redundancy", errors)
      mirrors = data["three_mirror_redundancy"].is_a?(Hash) ? data["three_mirror_redundancy"] : {}
      validate_string_list(mirrors["pool"], "models.yml three_mirror_redundancy.pool", errors, nonempty: true)
      valid_quorum = mirrors["quorum"].is_a?(Integer) && mirrors["quorum"].positive? &&
                     mirrors["pool"].is_a?(Array) && mirrors["quorum"] <= mirrors["pool"].size
      errors << "models.yml three_mirror_redundancy.quorum must be between 1 and pool size" unless valid_quorum
    end

    def validate_cli_lanes(data, errors)
      lanes = data["cli_lanes"].is_a?(Hash) ? data["cli_lanes"] : {}
      lanes.each { |name, row| validate_cli_lane(name, row, errors) }
    end

    def validate_cli_lane(name, row, errors)
      label = "models.yml cli_lanes.#{name}"
      strict_fields(row, %w[binary signed_in ask model_flag models login kind model_path_env], label, errors)
      return unless row.is_a?(Hash)

      %w[binary login].each do |field|
        errors << "#{label}.#{field} must be non-empty text" unless row[field].is_a?(String) && !row[field].strip.empty?
      end
      validate_cli_model_carrier(row, label, errors)
      validate_cli_optional_fields(row, label, errors)
      validate_string_list(row["ask"], "#{label}.ask", errors, nonempty: true)
      validate_string_list(row["models"], "#{label}.models", errors, nonempty: true)
      validate_cli_signed_in(row["signed_in"], label, errors)
    end

    def validate_cli_model_carrier(row, label, errors)
      if row.key?("model_flag")
        errors << "#{label}.model_flag must be non-empty text" unless row["model_flag"].is_a?(String) && !row["model_flag"].strip.empty?
      elsif !Array(row["ask"]).any? { |arg| arg.to_s.include?("%{model_path}") }
        errors << "#{label}.model_flag must be non-empty text when ask carries no %{model_path}"
      end
    end

    def validate_cli_optional_fields(row, label, errors)
      if row.key?("kind")
        errors << "#{label}.kind must be 'local' or absent" unless row["kind"] == "local"
      end
      if row.key?("model_path_env")
        errors << "#{label}.model_path_env must be non-empty text" unless
          row["model_path_env"].is_a?(String) && !row["model_path_env"].strip.empty?
      end
    end

    def validate_cli_signed_in(value, label, errors)
      strict_fields(value, %w[args match refuse], "#{label}.signed_in", errors)
      return unless value.is_a?(Hash)

      validate_string_list(value["args"], "#{label}.signed_in.args", errors, nonempty: true)
      errors << "#{label}.signed_in.match must be non-empty text" if value.key?("match") && !(value["match"].is_a?(String) && !value["match"].empty?)
      errors << "#{label}.signed_in.refuse must be non-empty text" if value.key?("refuse") && !(value["refuse"].is_a?(String) && !value["refuse"].empty?)
      errors << "#{label}.signed_in must declare match or refuse" unless value.key?("match") || value.key?("refuse")
    end

    def validate_openai_compatible(data, errors)
      endpoints = data["openai_compatible"].is_a?(Hash) ? data["openai_compatible"] : {}
      endpoints.each { |name, row| validate_openai_endpoint(name, row, errors) }
    end

    def validate_openai_endpoint(name, row, errors)
      label = "models.yml openai_compatible.#{name}"
      allowed = %w[base key_env keyless_max_concurrency concurrency_wait_seconds quota_bucket keyless daily_quota
                   privacy_posture]
      strict_fields(row, allowed, label, errors)
      return unless row.is_a?(Hash)

      errors << "#{label}.base must be a non-empty URL" unless row["base"].is_a?(String) && row["base"].match?(/\Ahttps?:\/\//)
      validate_string_list(row["key_env"], "#{label}.key_env", errors, nonempty: true)
      validate_endpoint_quota(row, label, errors)
      validate_endpoint_limits(row, label, errors)
      validate_endpoint_privacy(row, label, errors)
      validate_keyless_policy(row["keyless"], label, errors) if row.key?("keyless")
    end

    def validate_endpoint_quota(row, label, errors)
      return unless row.key?("daily_quota")

      errors << "#{label}.daily_quota must be a positive integer" unless
        row["daily_quota"].is_a?(Integer) && row["daily_quota"].positive?
    end

    def validate_endpoint_limits(row, label, errors)
      %w[keyless_max_concurrency concurrency_wait_seconds].each do |field|
        next unless row.key?(field)

        errors << "#{label}.#{field} must be positive" unless row[field].is_a?(Numeric) && row[field].positive?
      end
      return unless row.key?("quota_bucket")

      errors << "#{label}.quota_bucket must be non-empty text" unless row["quota_bucket"].is_a?(String) && !row["quota_bucket"].empty?
    end

    def validate_endpoint_privacy(row, label, errors)
      return unless row.key?("privacy_posture")

      valid = %w[anonymous logs_prompts trains_on_data unknown].include?(row["privacy_posture"])
      errors << "#{label}.privacy_posture must be one of: anonymous, logs_prompts, trains_on_data, unknown" unless valid
    end

    def validate_keyless_policy(value, label, errors)
      strict_fields(value, %w[tier usage_based_only isFree allow], "#{label}.keyless", errors)
      return unless value.is_a?(Hash)

      validate_keyless_tier(value, label, errors)
      validate_keyless_flags(value, label, errors)
      validate_string_list(value["allow"], "#{label}.keyless.allow", errors, nonempty: true) if value.key?("allow")
    end

    def validate_keyless_tier(value, label, errors)
      selectors = value.key?("allow") || value.key?("isFree")
      if value["tier"].nil?
        errors << "#{label}.keyless.tier must be non-empty text unless allow or isFree selects" unless selectors
      elsif value["tier"].empty?
        errors << "#{label}.keyless.tier must be non-empty text"
      end
    end

    def validate_keyless_flags(value, label, errors)
      if value.key?("usage_based_only")
        errors << "#{label}.keyless.usage_based_only must be boolean" unless [true, false].include?(value["usage_based_only"])
      end
      if value.key?("isFree")
        errors << "#{label}.keyless.isFree must be boolean" unless [true, false].include?(value["isFree"])
      end
    end

    def validate_ollama(data, errors)
      strict_fields(data["ollama"], %w[enabled default_base_url keep_alive max_num_ctx local_model_allowlist probe
                                      kv_cache_type warm_probe privacy_posture],
                    "models.yml ollama", errors)
      ollama = data["ollama"].is_a?(Hash) ? data["ollama"] : {}
      errors << "models.yml ollama.enabled must be boolean" unless [true, false].include?(ollama["enabled"])
      errors << "models.yml ollama.probe must be boolean" if ollama.key?("probe") && ![true, false].include?(ollama["probe"])
      validate_ollama_privacy(ollama, errors)
      %w[default_base_url keep_alive kv_cache_type].each do |field|
        errors << "models.yml ollama.#{field} must be non-empty text" unless ollama[field].is_a?(String) && !ollama[field].empty?
      end
      valid_context = ollama["max_num_ctx"].is_a?(Integer) && ollama["max_num_ctx"].positive?
      errors << "models.yml ollama.max_num_ctx must be a positive integer" unless valid_context
      validate_string_list(ollama["local_model_allowlist"], "models.yml ollama.local_model_allowlist", errors, nonempty: true)
      validate_ollama_warm_probe(ollama["warm_probe"], errors)
    end

    def validate_ollama_privacy(ollama, errors)
      return unless ollama.key?("privacy_posture")

      valid = %w[anonymous logs_prompts trains_on_data unknown].include?(ollama["privacy_posture"])
      errors << "models.yml ollama.privacy_posture must be one of: anonymous, logs_prompts, trains_on_data, unknown" unless valid
    end

    def validate_free_and_paid_tiers(data, errors)
      validate_free_tier(data, errors)
      validate_paid_tail(data, errors)
    end

    def validate_free_tier(data, errors)
      strict_fields(data["free_tier"], %w[neutral_latency_s unmeasured_timeout_s call_timeout_s],
                    "models.yml free_tier", errors)
      values = data["free_tier"].is_a?(Hash) ? data["free_tier"] : {}
      values.each do |field, value|
        errors << "models.yml free_tier.#{field} must be positive" unless value.is_a?(Numeric) && value.positive?
      end
    end

    def validate_paid_tail(data, errors)
      strict_fields(data["paid_tail"],
                    %w[enabled max_prompt_usd_per_m max_completion_usd_per_m run_cap_usd max_models],
                    "models.yml paid_tail", errors)
      paid = data["paid_tail"].is_a?(Hash) ? data["paid_tail"] : {}
      errors << "models.yml paid_tail.enabled must be boolean" unless [true, false].include?(paid["enabled"])
      %w[max_prompt_usd_per_m max_completion_usd_per_m run_cap_usd].each do |field|
        errors << "models.yml paid_tail.#{field} must be positive" unless paid[field].is_a?(Numeric) && paid[field].positive?
      end
      errors << "models.yml paid_tail.max_models must be a positive integer" unless paid["max_models"].is_a?(Integer) && paid["max_models"].positive?
    end

    def validate_media_lanes(data, errors)
      strict_fields(data["media_lanes"],
                    %w[budget_usd call_cap_usd image_tokens video_seconds timeouts catalog_merge providers image video],
                    "models.yml media_lanes", errors)
      media = data["media_lanes"].is_a?(Hash) ? data["media_lanes"] : {}
      validate_media_budgets(media, errors)
      validate_media_output_limits(media, errors)
      validate_media_timeouts(media, errors)
      validate_media_catalog_merge(media, errors)
      providers = validate_media_providers(media, errors)
      validate_media_kinds(media, providers, errors)
    end

    def validate_media_budgets(media, errors)
      %w[budget_usd call_cap_usd].each do |field|
        label = "models.yml media_lanes.#{field}"
        validate_fields(media[field], %w[image video], label, errors)
        values = media[field].is_a?(Hash) ? media[field] : {}
        %w[image video].each do |kind|
          errors << "#{label}.#{kind} must be positive" unless values[kind].is_a?(Numeric) && values[kind].positive?
        end
      end
    end

    def validate_media_output_limits(media, errors)
      %w[image_tokens video_seconds].each do |field|
        errors << "models.yml media_lanes.#{field} must be a positive integer" unless
          media[field].is_a?(Integer) && media[field].positive?
      end
    end

    def validate_media_timeouts(media, errors)
      strict_fields(media["timeouts"], %w[call_s video_total_s poll_s max_polls], "models.yml media_lanes.timeouts", errors)
      timeouts = media["timeouts"].is_a?(Hash) ? media["timeouts"] : {}
      timeouts.each do |field, value|
        errors << "models.yml media_lanes.timeouts.#{field} must be positive" unless value.is_a?(Numeric) && value.positive?
      end
    end

    def validate_media_catalog_merge(media, errors)
      strict_fields(media["catalog_merge"], %w[max_prompt_usd_per_m max_models], "models.yml media_lanes.catalog_merge", errors)
      catalog_merge = media["catalog_merge"].is_a?(Hash) ? media["catalog_merge"] : {}
      valid_prompt = catalog_merge["max_prompt_usd_per_m"].is_a?(Numeric) && catalog_merge["max_prompt_usd_per_m"].positive?
      errors << "models.yml media_lanes.catalog_merge.max_prompt_usd_per_m must be positive" unless valid_prompt
      valid_models = catalog_merge["max_models"].is_a?(Integer) && catalog_merge["max_models"].positive?
      errors << "models.yml media_lanes.catalog_merge.max_models must be a positive integer" unless valid_models
    end

    def validate_media_providers(media, errors)
      providers = media["providers"].is_a?(Hash) ? media["providers"] : {}
      providers.each { |name, row| validate_media_provider(name, row, errors) }
      providers
    end

    def validate_media_provider(name, row, errors)
      label = "models.yml media_lanes.providers.#{name}"
      strict_fields(row, %w[env base], label, errors)
      return unless row.is_a?(Hash)

      validate_string_list(row["env"], "#{label}.env", errors, nonempty: true)
      return unless row.key?("base")

      errors << "#{label}.base must be a non-empty URL" unless row["base"].is_a?(String) && row["base"].match?(/\Ahttps?:\/\//)
    end

    def validate_media_kinds(media, providers, errors)
      %w[image video].each do |kind|
        rows = media[kind]
        unless rows.is_a?(Array) && !rows.empty?
          errors << "models.yml media_lanes.#{kind} must be a non-empty list"
          next
        end
        rows.each_with_index do |row, index|
          validate_media_lane(kind, row, index, providers, errors)
        end
      end
    end

    def validate_media_lane(kind, row, index, providers, errors)
      label = "models.yml media_lanes.#{kind}[#{index}]"
      strict_fields(row, %w[provider model price_id usd_per_call usd_per_second image_tokens], label, errors)
      return unless row.is_a?(Hash)

      valid_provider = row["provider"].is_a?(String) && providers.key?(row["provider"])
      errors << "#{label}.provider must name a declared media provider" unless valid_provider
      errors << "#{label}.model must be non-empty text" unless row["model"].is_a?(String) && !row["model"].empty?
      validate_media_lane_price_id(row, label, errors)
      validate_media_lane_costs(row, label, errors)
      if row.key?("image_tokens")
        valid_tokens = row["image_tokens"].is_a?(Integer) && row["image_tokens"].positive?
        errors << "#{label}.image_tokens must be a positive integer" unless valid_tokens
      end
    end

    def validate_media_lane_price_id(row, label, errors)
      return unless row.key?("price_id")

      errors << "#{label}.price_id must be non-empty text" unless row["price_id"].is_a?(String) && !row["price_id"].empty?
    end

    def validate_media_lane_costs(row, label, errors)
      %w[usd_per_call usd_per_second].each do |field|
        next unless row.key?(field)

        errors << "#{label}.#{field} must be positive" unless row[field].is_a?(Numeric) && row[field].positive?
      end
    end

    def strict_fields(value, allowed, label, errors)
      validate_fields(value, allowed, label, errors)
    end

    def validate_fields(value, allowed, label, errors)
      unless value.is_a?(Hash)
        errors << "#{label} must be a mapping"
        return false
      end
      unknown = value.keys.map(&:to_s) - allowed
      errors << "#{label} has unknown field(s): #{unknown.sort.join(', ')}" unless unknown.empty?
      true
    end

    def validate_string_list(value, label, errors, nonempty: false)
      valid = value.is_a?(Array) && (!nonempty || !value.empty?) &&
              value.all? { |item| item.is_a?(String) && !item.strip.empty? }
      errors << "#{label} must be a list of non-empty strings" unless valid
      valid
    end

    # The warm probe is optional, but when declared its four fields are read
    # straight by LaneHealth.warm_probe, so a wrong type there is a silent
    # fallback rather than a startup error.
    def validate_ollama_warm_probe(spec, errors)
      return if spec.nil?

      label = "models.yml ollama.warm_probe"
      return unless validate_fields(spec, %w[enabled model interval_s num_predict num_ctx], label, errors)

      errors << "#{label}.enabled must be boolean" unless [true, false].include?(spec["enabled"])
      errors << "#{label}.model must be non-empty text" unless nonempty_text?(spec["model"])
      %w[interval_s num_predict num_ctx].each do |field|
        next unless spec.key?(field)

        errors << "#{label}.#{field} must be a positive integer" unless positive_integer?(spec[field])
      end
    end

    def nonempty_text?(value) = value.is_a?(String) && !value.strip.empty?

    def positive_integer?(value) = value.is_a?(Integer) && value.positive?

    private_class_method(
      :validate_routing_and_policy,
      :validate_continuity,
      :validate_openrouter,
      :validate_ferrum_web_chat,
      :validate_ferrum_provider,
      :validate_mirror_redundancy,
      :validate_cli_lanes,
      :validate_cli_lane,
      :validate_cli_model_carrier,
      :validate_cli_optional_fields,
      :validate_cli_signed_in,
      :validate_openai_compatible,
      :validate_openai_endpoint,
      :validate_endpoint_quota,
      :validate_endpoint_limits,
      :validate_endpoint_privacy,
      :validate_keyless_policy,
      :validate_keyless_tier,
      :validate_keyless_flags,
      :validate_ollama,
      :validate_ollama_privacy,
      :validate_free_and_paid_tiers,
      :validate_free_tier,
      :validate_paid_tail,
      :validate_media_lanes,
      :validate_media_budgets,
      :validate_media_output_limits,
      :validate_media_timeouts,
      :validate_media_catalog_merge,
      :validate_media_providers,
      :validate_media_provider,
      :validate_media_kinds,
      :validate_media_lane,
      :validate_media_lane_price_id,
      :validate_media_lane_costs
    )
  end
end
