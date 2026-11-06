# frozen_string_literal: true

module Commands
  # Lists the declared environment knobs against the budget of Core::Knobs::LIMIT.
  class Knobs
    def initialize(world:, context:, out: $stdout)
      @out = out
    end

    def call(_argv)
      knobs = Core::Registry.load(:knobs).fetch("knobs")
      knobs.each { |name, k| @out.puts "#{name} #{k['type']} #{k['default'].inspect}" }
      @out.puts "knobs: #{knobs.size} of #{Core::Knobs::LIMIT}"
      0
    end
  end
end
