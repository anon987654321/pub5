# frozen_string_literal: true

require_relative "../../laws/engine"
require_relative "../fix/scan"
require_relative "../fix/report"

module Commands
  # `bin/master scan [tree|path] [--dry-run]`: every deterministic Law over
  # the scope's tracked and untracked files, reported as the boot - the
  # census totals, one device line per Law that found something, and, with
  # --dry-run, the fix0 device counting what the deterministic rewrites
  # would touch. A scan writes nothing outside tmp/fix (the manifest's verbs
  # say so); the repairs themselves are `bin/master fix`'s to make.
  class Scan
    USAGE = "usage: bin/master scan [tree|path] [--dry-run]"

    def initialize(world:, context:, out: $stdout)
      @world = world
      @context = context
      @out = out
    end

    def call(argv)
      args = argv.dup
      dry_run = args.delete("--dry-run")
      return usage if args.size > 1 || args.any? { |a| a.start_with?("-") }

      scope = args.first || "."
      return usage unless File.exist?(File.expand_path(scope, @world.manifest.root))

      laws = ::Fix::Scan.scanning(Law.load!)
      result = ::Fix::Scan.new(world: @world, laws:, scope:).call
      repair, held = dry_run ? ::Fix::Report.census(result, laws) : [nil, []]
      @out.print ::Fix::Report.boot(result, laws:, scope:, root: @world.manifest.root,
                                    dry_run:, repair:, held:)
      0
    end

    private

    def usage
      @out.puts USAGE
      64
    end
  end
end
