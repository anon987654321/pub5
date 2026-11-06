# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/structural.rb:146 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 5ebb2d4b2bcfc0d5
require_relative "master/law/structural"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:EXPLICIT) do
          detector ExplicitLaw
          tags %i[EXPLICIT CONVENTION]
          fix "no implicit requires or magic coupling"
          example_path "/repo/lib/example.rb"
          bad %(autoload :Thing, "thing"\n)
          good %(require_relative "thing"\n)
        end
      end
    end
  end
end
