# frozen_string_literal: true

module Operator
  # Maps RAILS path ownership to complete app suites and gives each child its
  # own bundle, independent of the MASTER bundle that launched the operator.
  # Brgen, Amber and BSDPorts consume __shared; Mr Damascy is public but standalone.
  module TestScope
    SHARED_APPS = %w[brgen amber bsdports].freeze
    APP_SUITES = %w[brgen amber bsdports mrdamascy].freeze
    BUNDLE_CONTEXT = %w[
      BUNDLE_APP_CONFIG BUNDLE_BIN BUNDLE_BIN_PATH BUNDLE_DEPLOYMENT
      BUNDLE_DISABLE_SHARED_GEMS BUNDLE_FROZEN BUNDLE_GEMFILE BUNDLE_IGNORE_CONFIG
      BUNDLE_JOBS BUNDLE_LOCKFILE BUNDLE_ONLY BUNDLE_PATH BUNDLE_RETRY
      BUNDLE_USER_CONFIG BUNDLE_USER_HOME BUNDLE_VERSION BUNDLE_WITH BUNDLE_WITHOUT
      BUNDLER_SETUP BUNDLER_VERSION GEM_HOME GEM_PATH RUBYOPT RUBYLIB
    ].freeze

    module_function

    def rails_apps(parts)
      selected = Array(parts).map(&:to_s)
      APP_SUITES.select do |app|
        selected.include?("RAILS") || selected.include?(app) ||
          (selected.include?("__shared") && SHARED_APPS.include?(app))
      end
    end

    def app_environment(root:, app:, inherited_env: ENV)
      env = BUNDLE_CONTEXT.to_h { |key| [key, nil] }
      env["BUNDLE_GEMFILE"] = File.join(root, "RAILS", app, "Gemfile")
      inherited_env.each_key { |key| env[key] = nil if key.start_with?("BUNDLER_ORIG_") }
      env
    end
  end
end
