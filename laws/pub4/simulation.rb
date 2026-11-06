# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:2144 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 8047777b3a0f3523
require_relative "master/law/universal"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:SIMULATION) do
          tags %i[ANTI_SIMULATION DENSITY]
          fix "future tense implies without evidence - use indicative past"
          bad %(warn "the deploy will restart relayd"\n)
          good %(assert ok, "this test would pass having measured nothing"\n)
          check do |src, path|
            next [] unless path.to_s.end_with?(".rb", ".md", ".txt", ".erb")

            src.each_line.with_index(1).filter_map do |line, n|
              next if line.strip.start_with?("#")
              next unless line.match?(SIMULATION_PROMISE) || line.match?(SIMULATION_REPORT)

              finding(line: n, message: "simulation language - rewrite in indicative past or present tense")
            end
          end
        end
      end
    end
  end
end
