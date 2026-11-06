# frozen_string_literal: true

module Core
  # A capability manifest, in the spirit of pledge(2) and unveil(2): a plugin
  # names the World verbs it may use and, per verb, what it may reach. Core
  # refuses anything the manifest does not declare. The verb set is closed.
  #
  #   name: fix
  #   verbs:
  #     read:   ["**/*.rb"]         # paths, globs relative to the root
  #     write:  ["master/fix/**"]
  #     render: ["master/face/templates/**"]
  #     exec:   [ruby]              # command names (argv[0]'s basename)
  #     net:    [api.anthropic.com] # hosts
  #     llm:    [anthropic]         # providers in registry/models.yml
  #     git:    [status, diff]      # git subcommands
  #
  # Writes are refused on registry/paths.yml's protected paths whatever the
  # manifest says: /fix may propose a change there, never make one. The one
  # exception is a generated file (paths.yml generated), which only the
  # command named as its generator may write.
  class Manifest
    VERBS = %i[read write exec net llm git render].freeze
    PATH_VERBS = %i[read write render].freeze
    GLOB = File::FNM_PATHNAME | File::FNM_EXTGLOB | File::FNM_DOTMATCH

    attr_reader :name, :root

    def self.load(path, root: ROOT, protected_paths: nil)
      data = Registry.yaml(path)
      new(name: data.fetch("name"), verbs: data.fetch("verbs", {}), root:, protected_paths:)
    end

    def initialize(name:, verbs:, root: ROOT, protected_paths: nil, generated: nil)
      @name = name.to_s
      @root = File.realpath(root)
      @verbs = verbs.to_h.transform_keys(&:to_sym)
      unknown = @verbs.keys - VERBS
      raise Refusal.new(:manifest, @name, "unknown verbs #{unknown.join(', ')}") if unknown.any?

      @protected = protected_paths || Registry.load(:paths).fetch("protected")
      @generated = generated || (protected_paths ? {} : Registry.load(:paths).fetch("generated"))
    end

    def declared?(verb) = @verbs.key?(verb.to_sym)

    # Returns the checked target (a path made absolute and confined to the
    # root, or the name as given) or raises Refusal.
    def check!(verb, target)
      verb = verb.to_sym
      raise Refusal.new(verb, target, "#{verb} is not a World verb") unless VERBS.include?(verb)
      raise Refusal.new(verb, target, "#{@name} does not declare #{verb}") unless declared?(verb)
      return check_path!(verb, target) if PATH_VERBS.include?(verb)

      allowed = Array(@verbs[verb]).map(&:to_s)
      raise Refusal.new(verb, target, "#{@name} does not declare #{target} under #{verb}") unless allowed.include?(target.to_s)

      target.to_s
    end

    def protected?(relative) = @protected.any? { |glob| File.fnmatch?(glob, relative, GLOB) }

    private

    def check_path!(verb, target)
      relative = confine!(verb, target.to_s)
      unless Array(@verbs[verb]).any? { |glob| File.fnmatch?(glob, relative, GLOB) }
        raise Refusal.new(verb, relative, "#{@name} does not declare this path under #{verb}")
      end
      if verb == :write && protected?(relative) && @generated.dig(relative, "by") != @name
        raise Refusal.new(verb, relative, "protected by registry/paths.yml")
      end

      File.join(@root, relative)
    end

    # The path relative to the root, after resolving every symlink that exists,
    # so neither ../ nor a link can reach outside it.
    def confine!(verb, target)
      absolute = File.expand_path(target, @root)
      existing = absolute
      existing = File.dirname(existing) until File.exist?(existing) || existing == "/"
      resolved = File.join(File.realpath(existing), absolute.delete_prefix(existing))
      resolved = resolved.chomp("/")
      unless resolved == @root || resolved.start_with?("#{@root}/")
        raise Refusal.new(verb, target, "outside the root #{@root}")
      end

      resolved.delete_prefix("#{@root}/")
    end
  end
end
