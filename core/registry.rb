# frozen_string_literal: true

require "yaml"
require "date"

module Core
  # The one registry loader. registry/<name>.yml is read only if
  # registry/schemas/<name>.yml exists, and only returned if it validates:
  # a registry without a schema, or one that drifted from it, is refused
  # instead of half-read.
  module Registry
    DIR = File.join(ROOT, "registry")
    PERMITTED = [Date, Time, Symbol].freeze

    @cache = {}

    module_function

    def names(dir: DIR)
      Dir.children(File.join(dir, "schemas")).grep(/\.yml\z/).map { |f| f.delete_suffix(".yml") }.sort
    end

    def load(name, dir: DIR)
      name = name.to_s
      key = [dir, name]
      return @cache[key] if @cache.key?(key)

      schema_path = File.join(dir, "schemas", "#{name}.yml")
      raise Refusal.new(:registry, name, "no schema at registry/schemas/#{name}.yml") unless File.file?(schema_path)

      data = yaml(File.join(dir, "#{name}.yml"))
      errors = Schema.validate(data, yaml(schema_path))
      raise Refusal.new(:registry, name, "schema: #{errors.first(5).join('; ')}") if errors.any?

      @cache[key] = deep_freeze(data)
    end

    def yaml(path) = YAML.safe_load_file(path, permitted_classes: PERMITTED, aliases: true)

    def parse(text) = YAML.safe_load(text, permitted_classes: PERMITTED, aliases: true)

    def reset! = @cache.clear

    def deep_freeze(value)
      case value
      when Hash then value.each_value { |v| deep_freeze(v) }
      when Array then value.each { |v| deep_freeze(v) }
      end
      value.freeze
    end
  end
end
