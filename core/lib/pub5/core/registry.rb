# frozen_string_literal: true
require "yaml"
require_relative "errors"

module Pub5
  module Core
    class Registry
      def self.load(path, required: [])
        data = YAML.safe_load_file(path, permitted_classes: [], permitted_symbols: [], aliases: false)
        raise InvalidRegistry, "#{path}: expected a mapping" unless data.is_a?(Hash)
        raise InvalidRegistry, "#{path}: schema must be 1" unless data["schema"] == 1
        missing = required.map(&:to_s) - data.keys
        raise InvalidRegistry, "#{path}: missing #{missing.join(", ")}" unless missing.empty?
        data.freeze
      rescue Psych::Exception => e
        raise InvalidRegistry, "#{path}: #{e.message}"
      end
    end
  end
end
