# frozen_string_literal: true

require_relative "../contracts/contracts"

module Commands
  # Rewrites every file registry/paths.yml lists as generated. Only this
  # command's manifest may write them.
  class Generate
    def initialize(world:, context:, out: $stdout)
      @world = world
      @out = out
    end

    def call(_argv)
      Core::Registry.load(:paths).fetch("generated").each_key do |file|
        @world.write(file, Contracts.render(file))
        @out.puts "generate: #{file}"
      end
      0
    end
  end
end
