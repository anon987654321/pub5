# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/structural.rb:250 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 37f01f02caeafc42
require_relative "master/law/structural"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:PATTERN_EXTRACTION) do
          detector PatternExtractionLaw
          tags %i[DESIGN OPPORTUNITY]
          source "MASTER-native - extract recurring structure"
          ask "Is the code close to a known reusable pattern whose extraction would genuinely reduce complexity rather than add ceremony?"
          fix "Extract a pattern only when recurring structure earns the abstraction."
          bad <<~'X'
          if cache.hit?; cache.read; else; fetch; cache.write; end
          X
          good <<~'X'
          result = Cache.fetch(key) { fetch }
          X
          proved_by "test/laws/imported_pub4_proofs_test.rb"
        end
      end
    end
  end
end
