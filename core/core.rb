# frozen_string_literal: true

# The kernel. Everything that touches the outside (files, processes, the
# network, models, git, templates, the environment) goes through this
# directory and nowhere else; the ONE_IMPLEMENTATION_PER_OPERATION Law fails
# a second copy anywhere in the tree.
module Core
  ROOT = File.expand_path("..", __dir__).freeze

  # Raised whenever core declines to do something. The verb and the target
  # travel with it so the caller's report names what was refused and why.
  class Refusal < StandardError
    attr_reader :verb, :target

    def initialize(verb, target, reason)
      @verb = verb
      @target = target
      super("refused #{verb} #{target}: #{reason}")
    end
  end
end

require_relative "atomic"
require_relative "schema"
require_relative "registry"
require_relative "knobs"
require_relative "ledger"
require_relative "manifest"
require_relative "http"
require_relative "llm"
require_relative "parse_gate"
require_relative "world"
