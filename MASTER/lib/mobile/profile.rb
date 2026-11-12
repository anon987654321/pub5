# frozen_string_literal: true

require_relative "env"

module Master
  module Mobile
    # Switches MASTER to its phone shape when Termux is detected or
    # MASTER_PROFILE=mobile is set. It sets environment defaults from
    # data/mobile.yml and nothing else; the constitution is unchanged.
    class Profile
      # config is read on first use, not at initialize: on a desktop boot the
      # profile never activates, Mobile.config never loads, and yaml (psych)
      # stays unactivated until the locked copy can be pinned.
      def initialize(config: nil, env: ENV)
        @config = config
        @env = env
      end

      def config = @config ||= Mobile.config

      def active? = Env.mobile?(@env)

      def activate!
        return false unless active?

        @env["MASTER_PROFILE"] = "mobile"
        config.fetch("env", {}).each { |key, value| @env[key] ||= value.to_s }
        true
      end

      def min_ruby = config.dig("profile", "min_ruby") || "3.2.0"

      def auto_approve?
        chosen = @env["MASTER_MOBILE_AUTO_APPROVE"].to_s
        chosen.empty? ? config.dig("packages", "auto_approve") == true : chosen == "1"
      end
    end
  end
end
