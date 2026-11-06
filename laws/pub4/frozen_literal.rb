# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/lexical.rb:155 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 5ee0fc49eaec395e
require_relative "master/law/lexical"

module Master
  module Review
    module Scan
      module Laws
  ::Law.define(:FROZEN_LITERAL) do
    tags %i[PERFORMANCE]
    fix "missing frozen_string_literal magic comment"
    bad "value = 1\n# frozen_string_literal: true\n"
    good "#!/usr/bin/env ruby\n# frozen_string_literal: true\n\nvalue = 1\n"
    check do |src, path|
      leading = src.each_line.take_while { |line| line.strip.empty? || line.lstrip.start_with?("#") }

      next [] if leading.any? { |line| line.include?("frozen_string_literal") }
      magic = "# frozen_string_literal: true"
      [finding(line: 1, message: "add #{magic}")]
    end
  end
      end
    end
  end
end
