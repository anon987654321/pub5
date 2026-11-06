# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/lexical.rb:249 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: e94dba98c496356a
require_relative "master/law/lexical"

module Master
  module Review
    module Scan
      module Laws
  ::Law.define(:HARDCODED_ABSOLUTE_PATH) do
    tags %i[PORTABILITY]
    fix "a path to one machine's home directory in code"
    bad "ROOT = \"/Users/mac/Documents/GitHub/pub4\"\n"
    good "ROOT = File.expand_path(\"..\", __dir__)\n"
    check do |src, path|
      next [] if path.to_s.match?(%r{(?:\A|/)(?:test|spec)/})

      src.each_line.with_index(1).filter_map do |line, number|
        next if line.match?(%r{\A\s*(?:#|//|/?\*|<!--)})
        next unless line.match?(%r{/Users/[a-z][\w.-]*/|\b[A-Z]:[/\\](?:Users|priv|home)\b}i)

        finding(line: number, message: "machine-specific path - derive it from __dir__, ENV or config")
      end
    end
  end
      end
    end
  end
end
