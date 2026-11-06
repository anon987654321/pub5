# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/lexical.rb:188 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: c4461bc8a5a21fc0
require_relative "master/law/lexical"

module Master
  module Review
    module Scan
      module Laws
  ::Law.define(:TRAILING_WHITESPACE) do
    tags %i[HYGIENE]
    fix "trailing whitespace"
    bad "value = 1   \n"
    good "value = 1\n\n"
    check do |src, path|
      src.each_line.with_index(1).filter_map do |line, n|
        finding(line: n, message: "trailing whitespace") if line.match?(/[ \t]+\n?\z/)
      end
    end
  end
      end
    end
  end
end
