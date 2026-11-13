# frozen_string_literal: true

module Master
  module CLI
    # Destructive slash commands and configurable blocking review (security.yml).
    module DestructiveRoutes
      FALLBACK = %w[clear rebuild resync shell rollback].freeze

      module_function

      # Resolved on first use, not at require time: this file is requirable
      # before lib/master.rb (the command-palette contract test requires the
      # route stage directly), and Master.data_path does not exist yet then.
      def security_path
        @security_path ||= Master.data_path("security.yml").freeze
      end

      def patterns_path
        @patterns_path ||= Master.data_path("patterns.yml").freeze
      end

      def destructive_commands
        @destructive_commands ||= load_destructive_commands
      end

      def destructive_command?(name)
        destructive_commands.include?(name.to_s)
      end

      def destructive_route?(ctx)
        return true if destructive_command?(ctx.command.to_s)
        return true if ctx.last_tool_tier == :dangerous

        false
      end

      def blocking_review?
        return false if ENV["MASTER_BLOCKING_REVIEW"] == "0"

        defaults = Master.load_yaml(security_path) || {}
        defaults.dig("tools", "custom", "require_review_for_destructive") != false
      end

      def load_destructive_commands
        return FALLBACK unless File.exist?(patterns_path)

        data = Master.patterns_config
        list = Array(data&.dig("infer", "destructive")).map(&:to_s).reject(&:empty?)
        raise "destructive command policy is empty: #{patterns_path}" if list.empty?

        list.freeze
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "destructive_routes.load")
        raise "destructive command policy unreadable: #{e.class}: #{e.message}"
      end
    end
  end
end
