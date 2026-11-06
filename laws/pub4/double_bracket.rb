# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/javascript.rb:249 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 9d5340c5d079c493
require_relative "master/law/javascript"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:DOUBLE_BRACKET) do
          tags %i[ROBUSTNESS]
          fix "use [[ ]] over [ ]"
          bad "#!/bin/zsh\nif [ -f x ]; then echo y; fi\n"
          good "#!/bin/zsh\nif [[ -f x ]]; then echo y; fi\n"
          check do |src, path|
            # POSIX sh shebang — [[ ]] is a keyword only in zsh/bash/ksh, not in sh.
            # A sourced library has no shebang, so it declares its dialect in its
            # opening comment instead, the way lib/ci_lock.sh does.
            next [] if src.lines.first.to_s.match?(%r{#!/(?:usr/bin/env sh|bin/sh)\b|\A#\s*POSIX sh\b})
            # A comment quoting `[ -x file ]` describes a test rather than running one.
            scan_lines(without_comment_lines(src), /(?<!\[)\[\s+[^\[]/, message: "[ ] test - use [[ ]] in zsh")
          end
        end
      end
    end
  end
end
