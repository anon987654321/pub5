# frozen_string_literal: true

module Operator
  # Maps RAILS path ownership to the complete app suites that can be affected.
  # Brgen, Amber and BSDPorts consume __shared; Mr Damascy is a public but
  # standalone app and must not be silently omitted from focused proof.
  module TestScope
    SHARED_APPS = %w[brgen amber bsdports].freeze
    APP_SUITES = %w[brgen amber bsdports mrdamascy].freeze

    module_function

    def rails_apps(parts)
      selected = Array(parts).map(&:to_s)
      apps = APP_SUITES.select { |app| selected.include?(app) }
      apps |= SHARED_APPS if selected.include?("__shared")
      apps
    end
  end
end
