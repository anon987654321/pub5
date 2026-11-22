# frozen_string_literal: true

module Master
  module Io
    # Enforce one credential per provider. Distinct providers remain eligible
    # for ordinary failover; credentials for one provider are never rotated to
    # evade that provider's quota or rate limits.
    module KeyRotator
      LEGACY_OPENROUTER_KEY_ENV = %w[
        OPENROUTER_API_KEY OPENROUTER_API_KEY_2 OPENROUTER_API_KEY_3
      ].freeze

      module_function

      def env_vars
        vars = Master.models_config.dig("openrouter", "keys_env")
        configured = (Array(vars).map(&:to_s) + LEGACY_OPENROUTER_KEY_ENV).reject(&:empty?).uniq
        enforce_single_key!("openrouter", configured)
        populated = configured.select { |var| ENV[var].to_s.length >= Master::MIN_API_KEY_LENGTH_HEURISTIC }
        populated.empty? ? %w[OPENROUTER_API_KEY] : populated
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "KeyRotator.env_vars")
        raise
      end

      # The hosted endpoint's declared key environment variable(s)
      # (models.yml openai_compatible.<name>.key_env).
      def hosted_env_vars(name)
        vars = Master.models_config.dig("openai_compatible", name.to_s, "key_env")
        configured = Array(vars).map(&:to_s).reject(&:empty?)
        enforce_single_key!(name, configured)
        configured
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "KeyRotator.hosted_env_vars", provider: name.to_s)
        raise
      end

      def keys(vars = env_vars)
        populated = Array(vars).map { |var| [var, ENV[var].to_s] }
                             .select { |_var, key| key.length >= Master::MIN_API_KEY_LENGTH_HEURISTIC }
        enforce_single_key!("provider", populated.map(&:first))
        populated.map(&:last).uniq
      end

      def hosted_name(model)
        id = model.to_s
        name = id.split(":", 2).first
        return unless id.include?(":") && !name.to_s.empty?

        name unless hosted_env_vars(name).empty?
      end

      def active_key
        keys.first
      end

      def active_key_for(name)
        keys(hosted_env_vars(name)).first
      end

      def configure_current!
        key = active_key
        return false if key.nil?

        RubyLLM.configure { |cfg| cfg.openrouter_api_key = key }
        true
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "KeyRotator.configure_current!")
        false
      end

      # Retained as a compatibility hook for existing callers. Quota failures
      # must fail over to a different provider, never to another key.
      def rotate_for(_model)
        false
      end

      def positions(_name) = 0

      def enforce_single_key!(provider, vars)
        populated = Array(vars).uniq.select do |var|
          ENV[var].to_s.length >= Master::MIN_API_KEY_LENGTH_HEURISTIC
        end
        credentials = populated.map { |var| ENV[var].to_s }.uniq
        return true if credentials.size <= 1

        raise ArgumentError,
              "provider #{provider} has multiple distinct populated credentials (#{populated.join(', ')}); configure one key only"
      end
    end
  end
end
