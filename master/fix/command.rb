# frozen_string_literal: true

require_relative "../../laws/engine"
require_relative "run"
require_relative "../models/dispatch"

module Commands
  # `bin/master fix [tree|path] [--dry-run] [--focus LAW] [--visual]`, the one
  # entry to /fix (pub4's MASTER/bin/fix-here wrapper is gone: its lane
  # proof, orphan reap and stall stop live in the run).
  #
  # The target is a tree or path in this repository, or the top of another
  # git repository. Another repository gets a World rooted there with this
  # command's own declared verbs from registry/commands.yml, so core enforces
  # the same manifest and the same protected paths on it.
  class Fix
    USAGE = "usage: bin/master fix [tree|path] [--dry-run] [--focus LAW] [--visual]"

    def initialize(world:, context:, out: $stdout, knobs: Core::Knobs.default)
      @world = world
      @context = context
      @out = out
      @knobs = knobs
    end

    def call(argv)
      options = parse(argv.dup) or return usage
      world, scope = target(options[:target])
      run = nil
      say = ->(line) { run ? run.pulse(line) : @out.puts(line) }
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + ::Fix::Run::RUN_BUDGET_S
      model = Models::Dispatch.build(world, knobs: @knobs, say:, deadline:, pace_load: true)
      run = ::Fix::Run.new(world:, scope:, laws: Law.load!, model:, writer: @knobs.fetch("PUB5_WRITER"),
                           focus: options[:focus], dry_run: options[:dry_run], out: @out,
                           visual: options[:visual] ? visual_lane(world, say) : nil)
      run.call
    rescue ArgumentError => e
      @out.puts "fix: #{e.message}"
      64
    end

    private

    def parse(args)
      options = { dry_run: args.delete("--dry-run"), visual: args.delete("--visual") }
      if (i = args.index("--focus"))
        options[:focus] = args.delete_at(i + 1) or return
        args.delete_at(i)
      end
      return if args.size > 1 || args.any? { |a| a.start_with?("-") }

      options.merge(target: args.first || ".")
    end

    def usage
      @out.puts USAGE
      64
    end

    def target(arg)
      root = @world.manifest.root
      full = File.expand_path(arg, root)
      inside = full == root || full.start_with?("#{root}/")
      return [@world, full == root ? "." : full.delete_prefix("#{root}/")] if inside
      raise ArgumentError, "#{arg} is not a git repository top" unless File.directory?(File.join(full, ".git"))

      verbs = Core::Registry.load(:commands).fetch("commands").fetch("fix").fetch("verbs")
      manifest = Core::Manifest.new(name: "fix", verbs:, root: full)
      [Core::World.new(manifest:, ledger: @world.ledger, knobs: @knobs), "."]
    end

    # The reviewer is pinned to PUB5_FIX_REVIEWER, a different model from the
    # author; without one a visible change stays uncleared.
    def visual_lane(world, say)
      require_relative "visual/lane"
      reviewer = @knobs.fetch("PUB5_FIX_REVIEWER")
      ::Fix::Visual::Lane.new(world:, reviewer: reviewer && pinned(world, reviewer, say),
                              author: @knobs.fetch("PUB5_MODEL"), chrome: @knobs.fetch("PUB5_CHROME"))
    end

    def pinned(world, id, say)
      catalog = Models::Catalog.new
      lanes = Models::Lanes.new(catalog:, store: Models::Lanes::Store.new(world))
      router = Models::Router.new(catalog:, lanes:, knobs: @knobs)
      router.define_singleton_method(:chain) { |_task| [id] }
      Models::Dispatch.new(world:, catalog:, lanes:, router:, gate: Models::Gate.new(lanes:, say:), knobs: @knobs, say:)
    end
  end
end
