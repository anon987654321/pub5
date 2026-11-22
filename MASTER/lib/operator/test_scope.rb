# frozen_string_literal: true

require_relative "../fix/rails_app"

module Operator
  # Maps RAILS path ownership to complete app suites and gives each child its
  # own bundle. App identity and shared-engine membership come from the existing
  # RailsApp reader: apps.yml plus the Gemfiles that actually mount pub5-shared.
  module TestScope
    BUNDLE_CONTEXT = %w[
      BUNDLE_APP_CONFIG BUNDLE_BIN BUNDLE_BIN_PATH BUNDLE_DEPLOYMENT
      BUNDLE_DISABLE_SHARED_GEMS BUNDLE_FROZEN BUNDLE_GEMFILE BUNDLE_IGNORE_CONFIG
      BUNDLE_JOBS BUNDLE_LOCKFILE BUNDLE_ONLY BUNDLE_PATH BUNDLE_RETRY
      BUNDLE_USER_CONFIG BUNDLE_USER_HOME BUNDLE_VERSION BUNDLE_WITH BUNDLE_WITHOUT
      BUNDLER_SETUP BUNDLER_VERSION GEM_HOME GEM_PATH RUBYOPT RUBYLIB
    ].freeze

    module_function

    def rails_apps(parts, root: File.expand_path("../../..", __dir__))
      selected = Array(parts).map(&:to_s)
      inventory = Master::Fix::RailsApp.app_paths(repo_root: root)
      apps = inventory.select { |_name, directory| directory.start_with?("RAILS/") }.keys
      shared = Master::Fix::RailsApp.engine_apps(repo_root: root)

      apps.select do |app|
        selected.include?("RAILS") || selected.include?(app) ||
          (selected.include?("__shared") && shared.include?(app))
      end
    end

    def app_environment(root:, app:, inherited_env: ENV)
      relative = Master::Fix::RailsApp.app_paths(repo_root: root)[app.to_s]
      raise ArgumentError, "#{app.inspect} is not a registered RAILS app" unless relative&.start_with?("RAILS/")

      env = BUNDLE_CONTEXT.to_h { |key| [key, nil] }
      env["BUNDLE_GEMFILE"] = File.join(root, relative, "Gemfile")
      inherited_env.each_key { |key| env[key] = nil if key.start_with?("BUNDLER_ORIG_") }
      env
    end
  end
end
