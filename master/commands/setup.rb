# frozen_string_literal: true

module Commands
  # Points this clone's git at the tracked .githooks/ directory, so every
  # commit passes .githooks/pre-commit (bin/master check --staged) and
  # .githooks/commit-msg (the subject format). Not opt-in: bin/setup runs it.
  class Setup
    HOOKS = %w[pre-commit commit-msg].freeze

    def initialize(world:, context:, out: $stdout)
      @world = world
      @out = out
    end

    def call(_argv)
      missing = HOOKS.reject { |h| File.executable?(File.join(@world.manifest.root, ".githooks", h)) }
      unless missing.empty?
        @out.puts "setup: NOT_RUN (.githooks lacks executable #{missing.join(', ')})"
        return 1
      end

      run = @world.git("config", "core.hooksPath", ".githooks")
      @out.puts run.ok? ? "setup: core.hooksPath .githooks (#{HOOKS.join(', ')})" : "setup: FAILED #{run.err.strip}"
      run.ok? ? 0 : 1
    end
  end
end
