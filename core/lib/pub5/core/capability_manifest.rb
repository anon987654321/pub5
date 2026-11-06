# frozen_string_literal: true
require "yaml"
require_relative "errors"

module Pub5
  module Core
    class CapabilityManifest
      VERBS = %w[read write exec net llm git render].freeze

      def self.load(path, root:)
        data = YAML.safe_load_file(path, permitted_classes: [], permitted_symbols: [], aliases: false)
        new(data, root: root)
      rescue Psych::Exception => e
        raise InvalidRegistry, "invalid capability manifest: #{e.message}"
      end

      def initialize(data, root:)
        raise InvalidRegistry, "manifest must be a mapping" unless data.is_a?(Hash)
        raise InvalidRegistry, "schema must be 1" unless data["schema"] == 1
        @paths = SafePath.new(root)
        @capabilities = Array(data["capabilities"])
      end

      def grant(verb)
        @capabilities.find { |row| row.is_a?(Hash) && row["verb"] == verb.to_s }
      end

      def allow!(verb, path: nil)
        verb = verb.to_s
        raise Denied, "unknown World verb: #{verb}" unless VERBS.include?(verb)
        row = grant(verb)
        raise Denied, "undeclared World verb: #{verb}" unless row
        return true unless path
        relative = @paths.relative(path)
        permitted = Array(row["paths"]).any? { |pattern| File.fnmatch?(pattern, relative, File::FNM_PATHNAME) }
        raise Denied, "path not granted for #{verb}: #{relative}" unless permitted
        true
      end

      def commands_for(verb)
        Array(grant(verb)&.fetch("commands", []))
      end
    end
  end
end
