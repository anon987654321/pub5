# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/javascript.rb:384 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 77889c872df42df2
require_relative "master/law/javascript"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:OPTIONAL_CHAINING_JS) do
          tags %i[READABILITY]
          fix "use ?. over && chains"
          bad "const name = user && user.name\n"
          good "const name = user?.name\n"
          check do |src, path|
            scan_lines(src, /(\w+)\s*&&\s*\1\.\w+/, message: "nil-guard chain - use optional chaining (?.) instead")
          end
        end
      end
    end
  end
end
