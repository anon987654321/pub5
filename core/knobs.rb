# frozen_string_literal: true

module Core
  # The only reader of the process environment. A name must be declared in
  # registry/knobs.yml (type, default, purpose) before anything can read it;
  # pub4 grew to 495 env names that way, so pub5 caps the list at LIMIT.
  class Knobs
    LIMIT = 40
    CASTS = {
      "string" => ->(v) { v },
      "integer" => ->(v) { Integer(v, 10) },
      "number" => ->(v) { Float(v) },
      "boolean" => ->(v) { %w[1 true yes on].include?(v.downcase) },
      "path" => ->(v) { File.expand_path(v) }
    }.freeze

    def self.default = @default ||= new(Registry.load(:knobs).fetch("knobs"))

    def self.fetch(name) = default.fetch(name)

    def initialize(declared, env: ENV)
      raise Refusal.new(:knobs, "registry/knobs.yml", "#{declared.size} knobs exceed the limit of #{LIMIT}") if declared.size > LIMIT

      @declared = declared
      @env = env
    end

    def names = @declared.keys

    def declared?(name) = @declared.key?(name.to_s)

    # The value of a declared knob, cast to its type; its default when unset.
    def fetch(name)
      name = name.to_s
      spec = @declared.fetch(name) { raise Refusal.new(:env, name, "not declared in registry/knobs.yml") }
      raw = @env[name]
      return default(spec) if raw.nil? || raw.empty?

      CASTS.fetch(spec.fetch("type")).call(raw)
    rescue ArgumentError, TypeError
      raise Refusal.new(:env, name, "#{raw.inspect} is not a #{spec['type']}")
    end

    # A relative default path is the repository's, not the caller's cwd.
    def default(spec)
      value = spec["default"]
      spec["type"] == "path" && value ? File.expand_path(value, ROOT) : value
    end

    # The first set value among several declared names (a provider key with aliases).
    def first(names) = Array(names).lazy.map { |n| fetch(n) }.find { |v| v && v != "" }
  end
end
