# frozen_string_literal: true

module Core
  # A small schema language for the registries, itself written in YAML:
  #
  #   type: object | array | string | integer | number | boolean | null | any
  #         (or a list of them)
  #   required: [keys]          properties: {key: schema}
  #   additional: false | schema (the schema every undeclared key must meet)
  #   items: schema             min_items / max_items: n
  #   enum: [values]            pattern: regex (strings only)
  #
  # validate returns a list of "path: problem" strings; empty means valid.
  module Schema
    TYPES = {
      "object" => Hash, "array" => Array, "string" => String, "integer" => Integer,
      "number" => Numeric, "boolean" => [TrueClass, FalseClass], "null" => NilClass
    }.freeze
    WORDS = %w[type required properties additional items min_items max_items enum pattern description].freeze

    module_function

    def validate(value, schema, path = "$")
      unknown = schema.keys - WORDS
      return ["#{path}: schema uses unknown words #{unknown.join(', ')}"] if unknown.any?

      errors = type_errors(value, schema, path)
      return errors if errors.any?

      errors += enum_errors(value, schema, path)
      errors += object_errors(value, schema, path) if value.is_a?(Hash)
      errors += array_errors(value, schema, path) if value.is_a?(Array)
      errors << "#{path}: #{value.inspect} does not match /#{schema['pattern']}/" if
        value.is_a?(String) && schema["pattern"] && !value.match?(Regexp.new(schema["pattern"]))
      errors
    end

    def type_errors(value, schema, path)
      types = Array(schema.fetch("type", "any"))
      return [] if types.include?("any")

      ok = types.any? { |t| Array(TYPES.fetch(t) { raise ArgumentError, "unknown type #{t}" }).any? { |k| value.is_a?(k) } }
      ok ? [] : ["#{path}: expected #{types.join(' or ')}, got #{value.class}"]
    end

    def enum_errors(value, schema, path)
      return [] unless schema["enum"]

      schema["enum"].include?(value) ? [] : ["#{path}: #{value.inspect} not in #{schema['enum'].inspect}"]
    end

    def object_errors(value, schema, path)
      props = schema.fetch("properties", {})
      errors = Array(schema["required"]).reject { |k| value.key?(k) }.map { |k| "#{path}: missing #{k}" }
      value.each do |key, child|
        sub = props[key.to_s]
        if sub
          errors += validate(child, sub, "#{path}.#{key}")
        elsif schema["additional"] == false
          errors << "#{path}: undeclared key #{key}"
        elsif schema["additional"].is_a?(Hash)
          errors += validate(child, schema["additional"], "#{path}.#{key}")
        end
      end
      errors
    end

    def array_errors(value, schema, path)
      errors = []
      errors << "#{path}: fewer than #{schema['min_items']} items" if schema["min_items"] && value.size < schema["min_items"]
      errors << "#{path}: more than #{schema['max_items']} items" if schema["max_items"] && value.size > schema["max_items"]
      value.each_with_index { |item, i| errors += validate(item, schema["items"], "#{path}[#{i}]") } if schema["items"]
      errors
    end
  end
end
