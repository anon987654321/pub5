# frozen_string_literal: true

require "yaml"
require_relative "model_catalogue_sections_guard"

module Master
  # Local integrity checks for model identities, tier membership, routes and
  # failover policy. External provider availability remains a separate probe.
  module ModelCatalogueGuard
    MODEL_TOP_LEVEL_FIELDS = %w[
      schema routing weights fallback_policy failover defaults model_defs models routes
      task_strengths vision_families tool_capable_prefixes operation_constraints continuity
      openrouter ferrum_web_chat three_mirror_redundancy subscription_lanes cli_lanes
      local_servers openai_compatible replicate_chat ollama free_tier paid_tail media_lanes
    ].freeze
    MODEL_MAP_SECTIONS = %w[
      routing weights fallback_policy failover defaults model_defs models routes task_strengths
      vision_families operation_constraints continuity openrouter ferrum_web_chat
      three_mirror_redundancy cli_lanes openai_compatible ollama free_tier paid_tail media_lanes
    ].freeze
    MODEL_ARRAY_SECTIONS = %w[tool_capable_prefixes subscription_lanes local_servers replicate_chat].freeze
    MODEL_SCORE_FIELDS = %w[quality speed cost].freeze

    # Tiers that may be an explicitly empty list. models.yml declares nsfw: []
    # with the comment "It is never included in the default, strong, review, or
    # fix tiers": the route's selection never reads the tier (ModelRouter
    # Selection special-cases task_type :nsfw onto the env-gated
    # local_uncensored lane, LaneSelection#nsfw_model_id), so the tier is a
    # marker that the route exists, not a pool. Demanding a non-empty list
    # forced either a fake model row into the catalogue or a boot that no
    # configuration could pass — every bin/master command died on the invariant
    # with "models.nsfw must be a non-empty list".
    EMPTY_ALLOWED_TIERS = %w[nsfw].freeze

    def self.validate(data, path:)
      errors = []
      validate_top_level(data, errors)
      validate_routing(data, path, errors)
      validate_scores_and_fallback(data, errors)
      tiers = declared_tiers(data)
      validate_failover(data, tiers, errors)
      definition_ids = validate_model_definitions(data, errors)
      validate_model_tiers(data, tiers, definition_ids, errors)
      validate_routes(data, tiers, errors)
      validate_task_strengths(data, errors)
      validate_vision_families(data, errors)
      validate_operation_constraints(data, tiers, errors)
      validate_extended_catalogues(data, tiers, errors)

      raise ArgumentError, errors.uniq.join("; ") unless errors.empty?
      true
    end

    def self.validate_scores(score, label, errors)
      unless score.is_a?(Hash)
        errors << "#{label} must be a mapping"
        return
      end
      missing = MODEL_SCORE_FIELDS - score.keys.map(&:to_s)
      errors << "#{label} is missing #{missing.join(', ')}" unless missing.empty?
      unknown = score.keys.map(&:to_s) - MODEL_SCORE_FIELDS
      errors << "#{label} has unknown field(s): #{unknown.sort.join(', ')}" unless unknown.empty?
      MODEL_SCORE_FIELDS.each do |field|
        value = score[field]
        errors << "#{label}.#{field} must be between 0 and 1" unless value.is_a?(Numeric) && value >= 0 && value <= 1
      end
    end

    class << self
      private

      def validate_top_level(data, errors)
        errors << "models.yml schema must be 1" unless data["schema"] == 1
        unknown = data.keys.map(&:to_s) - MODEL_TOP_LEVEL_FIELDS
        errors << "models.yml has unknown top-level field(s): #{unknown.sort.join(', ')}" unless unknown.empty?
        MODEL_MAP_SECTIONS.each do |section|
          errors << "models.yml #{section} must be a mapping" unless data[section].is_a?(Hash)
        end
        MODEL_ARRAY_SECTIONS.each do |section|
          values = data[section]
          valid = values.is_a?(Array) && values.all? { |value| value.is_a?(String) && !value.strip.empty? }
          errors << "models.yml #{section} must be a list of non-empty strings" unless valid
        end
      end

      def validate_routing(data, path, errors)
        routing = data["routing"].is_a?(Hash) ? data["routing"] : {}
        %w[enabled escalation_enabled].each do |field|
          errors << "models.yml routing.#{field} must be boolean" unless [true, false].include?(routing[field])
        end
        errors << "models.yml routing.strategy must be non-empty text" unless
          routing["strategy"].is_a?(String) && !routing["strategy"].strip.empty?
        errors << "models.yml routing.provider must be non-empty text" unless
          routing["provider"].is_a?(String) && !routing["provider"].strip.empty?
        validate_routing_provider(routing, path, errors)
      end

      def validate_routing_provider(routing, path, errors)
        providers_path = File.join(File.dirname(path), "providers.yml")
        return unless File.file?(providers_path)

        provider_data = Master.provider_config(root: File.dirname(File.dirname(providers_path)))
        return unless provider_data.is_a?(Hash) && !provider_data.key?(routing["provider"])

        errors << "models.yml routing.provider #{routing["provider"].inspect} is absent from providers.yml"
      end

      def validate_scores_and_fallback(data, errors)
        weights = data["weights"].is_a?(Hash) ? data["weights"] : {}
        validate_scores(weights, "models.yml weights", errors)
        defaults = data["defaults"].is_a?(Hash) ? data["defaults"] : {}
        validate_scores(defaults["score"], "models.yml defaults.score", errors)
        fallback = data["fallback_policy"].is_a?(Hash) ? data["fallback_policy"] : {}
        fallback_on = fallback["on"]
        valid_on = fallback_on.is_a?(Array) && !fallback_on.empty? &&
                   fallback_on.all? { |value| value.is_a?(String) && !value.strip.empty? }
        errors << 'models.yml fallback_policy must declare "on" as a non-empty list of error categories' unless valid_on
        errors << "models.yml fallback_policy has unknown field(s)" unless (fallback.keys.map(&:to_s) - ["on"]).empty?
      end

      def declared_tiers(data)
        data["models"].is_a?(Hash) ? data["models"] : {}
      end

      def validate_failover(data, tiers, errors)
        failover = data["failover"].is_a?(Hash) ? data["failover"] : {}
        sequence = failover["sequence"]
        valid_sequence = sequence.is_a?(Array) && !sequence.empty? && sequence.all? { |tier| tiers.key?(tier) }
        errors << "models.yml failover.sequence must reference declared model tiers" unless valid_sequence
        %w[cooldown_seconds skip_ttl_ms transient_skip_ttl_ms].each do |field|
          value = failover[field]
          errors << "models.yml failover.#{field} must be positive" unless value.is_a?(Numeric) && value.positive?
        end
        validate_failover_limits(failover, errors)
      end

      def validate_failover_limits(failover, errors)
        cooldown_tiers = failover["cooldown_tiers"]
        valid_cooldowns = cooldown_tiers.is_a?(Array) && !cooldown_tiers.empty? &&
                          cooldown_tiers.all? { |value| value.is_a?(Numeric) && value.positive? }
        errors << "models.yml failover.cooldown_tiers must be a list of positive durations" unless valid_cooldowns
        retries = failover["max_retries"]
        errors << "models.yml failover.max_retries must be a non-negative integer" unless retries.is_a?(Integer) && retries >= 0
      end

      def validate_model_definitions(data, errors)
        definitions = data["model_defs"].is_a?(Hash) ? data["model_defs"] : {}
        definition_ids = {}
        definitions.each do |name, row|
          validate_model_definition(name, row, definition_ids, errors)
        end
        errors << "models.yml model_defs must be a non-empty mapping" if definitions.empty?
        definition_ids
      end

      def validate_model_definition(name, row, definition_ids, errors)
        errors << "models.yml has invalid model definition name #{name.inspect}" unless name.to_s.match?(/\A[a-z][a-z0-9_]*\z/)
        unless row.is_a?(Hash)
          errors << "model_defs.#{name} must be a mapping"
          return
        end

        register_definition_id(name, row["id"], definition_ids, errors)
        validate_scores(row["score"], "model_defs.#{name}.score", errors)
        validate_context_window(row, "model_defs.#{name}", errors)
        extras = row.keys.map(&:to_s) - %w[id score context_window]
        errors << "model_defs.#{name} has unknown field(s): #{extras.sort.join(', ')}" unless extras.empty?
      end

      def register_definition_id(name, id, definition_ids, errors)
        unless id.is_a?(String) && id.match?(/\A[A-Za-z0-9][A-Za-z0-9._:\/+-]*\z/)
          errors << "model_defs.#{name}.id must be a valid model identifier"
        end
        return unless id.is_a?(String)

        errors << "model_defs contains duplicate model id #{id}" if definition_ids.key?(id)
        definition_ids[id] = name
      end

      def validate_model_tiers(data, tiers, definition_ids, errors)
        return unless data["models"].is_a?(Hash)

        tiers.each do |tier, rows|
          validate_model_tier(tier, rows, definition_ids, errors)
        end
      end

      def validate_model_tier(tier, rows, definition_ids, errors)
        name = tier.to_s
        errors << "models.yml has invalid model tier #{tier.inspect}" unless name.match?(/\A[a-z][a-z0-9_]*\z/)
        unless rows.is_a?(Array) && (!rows.empty? || EMPTY_ALLOWED_TIERS.include?(name))
          errors << "models.#{tier} must be a non-empty list"
          return
        end
        rows.each_with_index do |row, index|
          validate_model_tier_row(tier, row, index, definition_ids, errors)
        end
      end

      def validate_model_tier_row(tier, row, index, definition_ids, errors)
        label = "models.#{tier}[#{index}]"
        unless row.is_a?(Hash)
          errors << "#{label} must be a mapping"
          return
        end
        unknown_fields = row.keys.map(&:to_s) - %w[id score context_window]
        errors << "#{label} has unknown field(s): #{unknown_fields.sort.join(', ')}" unless unknown_fields.empty?
        id = row["id"]
        errors << "#{label} references unknown model id #{id.inspect}" unless id.is_a?(String) && definition_ids.key?(id)
        validate_scores(row["score"], "#{label}.score", errors)
        validate_context_window(row, label, errors)
      end

      def validate_context_window(row, label, errors)
        return unless row.key?("context_window")

        window = row["context_window"]
        errors << "#{label}.context_window must be a positive integer" unless window.is_a?(Integer) && window.positive?
      end

      def validate_routes(data, tiers, errors)
        routes = data["routes"].is_a?(Hash) ? data["routes"] : {}
        routes.each do |operation, tier|
          valid = tier.is_a?(String) && tiers.key?(tier)
          errors << "models.yml route #{operation} must reference a declared model tier" unless valid
        end
      end

      def validate_task_strengths(data, errors)
        task_strengths = data["task_strengths"].is_a?(Hash) ? data["task_strengths"] : {}
        task_strengths.each do |task, strengths|
          valid = strengths.is_a?(Array) && strengths.all? { |value| value.is_a?(String) && !value.strip.empty? }
          errors << "models.yml task_strengths.#{task} must be a list of non-empty strings" unless valid
        end
      end

      def validate_vision_families(data, errors)
        vision = data["vision_families"].is_a?(Hash) ? data["vision_families"] : {}
        %w[reads_images blind].each do |field|
          validate_vision_patterns(vision[field], field, errors)
        end
      end

      def validate_vision_patterns(patterns, field, errors)
        valid = patterns.is_a?(Array) && !patterns.empty? && patterns.all? { |value| value.is_a?(String) && !value.empty? }
        unless valid
          errors << "models.yml vision_families.#{field} must be a list of regex strings"
          return
        end
        patterns.each do |pattern|
          validate_vision_pattern(pattern, field, errors)
        end
      end

      def validate_vision_pattern(pattern, field, errors)
        Regexp.new(pattern)
      rescue RegexpError => error
        errors << "models.yml vision_families.#{field} has invalid regex: #{error.message}"
      end

      def validate_operation_constraints(data, tiers, errors)
        constraints = data["operation_constraints"].is_a?(Hash) ? data["operation_constraints"] : {}
        constraints.each do |operation, row|
          validate_operation_constraint(operation, row, tiers, errors)
        end
      end

      def validate_operation_constraint(operation, row, tiers, errors)
        label = "models.yml operation_constraints.#{operation}"
        unless row.is_a?(Hash)
          errors << "#{label} must be a mapping"
          return
        end
        unknown_fields = row.keys.map(&:to_s) - %w[min_quality preferred_tier]
        errors << "#{label} has unknown field(s): #{unknown_fields.sort.join(', ')}" unless unknown_fields.empty?
        quality = row["min_quality"]
        errors << "#{label}.min_quality must be between 0 and 1" unless quality.is_a?(Numeric) && quality >= 0 && quality <= 1
        valid_tier = row["preferred_tier"].is_a?(String) && tiers.key?(row["preferred_tier"])
        errors << "#{label}.preferred_tier is unknown" unless valid_tier
      end

      def validate_extended_catalogues(data, tiers, errors)
        ModelCatalogueSectionsGuard.validate(data, tiers:, errors:)
        errors << "models.yml tool_capable_prefixes must not be empty" if Array(data["tool_capable_prefixes"]).empty?
        errors << "models.yml subscription_lanes must not be empty" if Array(data["subscription_lanes"]).empty?
        errors << "models.yml replicate_chat must not be empty" if Array(data["replicate_chat"]).empty?
      end
    end

  end
end
