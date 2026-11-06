# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:2338 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 8d0a3de3e4929218
require_relative "master/law/universal"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:PLEDGE_STAGED) do
          tags %i[SECURITY]
          fix "Use Ground::Pledge's staged promises: stage 2 may only remove stage 1 authority, then lock unveil after paths are declared. Never widen a sealed stage or issue raw promises."
          bad %q(Master::Ground::Pledge.unveil("/", "r")) + "\n"
          good "Master::Ground::Pledge.stage1_boot!(root)\n"
          check do |src, path|
            wrapper = path.to_s.end_with?("lib/ground/pledge.rb")
            src.each_line.with_index(1).flat_map do |line, number|
              next [] if line.strip.start_with?("#")

              hits = []
              permissions = line[%r{\bunveil\(\s*["']/["']\s*,\s*["']([^"']*)["']}, 1]
              if permissions && !permissions.empty?
                hits << finding(line: number, message: %(unveil("/", "#{permissions}") leaves the filesystem open - deny the root first))
              end

              if !wrapper && line.match?(/\bPledge\.(?:pledge|unveil)\s*\(/)
                hits << finding(line: number, message: "raw pledge/unveil promise - call a Ground::Pledge stage helper")
              end
              hits
            end
          end
        end
      end
    end
  end
end
