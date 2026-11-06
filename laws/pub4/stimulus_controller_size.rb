# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/surface.rb:768 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: e817f8114ef05114
require_relative "master/law/surface"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:STIMULUS_CONTROLLER_SIZE) do
          tags %i[RAILS JAVASCRIPT]
          fix "Stimulus controllers stay focused"
          bad "export default class extends Controller {\n#{"  step();\n" * 199}}\n"
          good "export default class extends Controller {\n  connect() {}\n}\n"
          check do |src, path|
            limits = ::Master::Review::Scan::Laws.stimulus_limits

            max = limits.fetch("max_lines", 200).to_i
            # The declared pattern is Stimulus's own naming convention, so it is
            # narrower than the guess it replaces and finds the same four files in
            # the fleet — measured before the change.
            next [] unless path.to_s.match?(Regexp.new(limits.fetch("path_pattern", '_controller\.js$')))
            next [] unless src.match?(/Controller\s+extends|export default class/)

            lines = src.lines.size
            next [] if lines <= max
            [finding(line: 1, message: "Stimulus controller #{lines} lines - split at #{max} (data/laws.yml); move targets/actions out (progressive enhancement)")]
          end
        end
      end
    end
  end
end
