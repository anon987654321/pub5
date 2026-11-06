# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/lexical.rb:200 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 08ce49a03bbe1353
require_relative "master/law/lexical"

module Master
  module Review
    module Scan
      module Laws
  ::Law.define(:TODO_FIXME) do
    tags %i[COMPLETENESS]
    fix "unresolved work markers"
    bad "  # FIXME: the retry has no cap\n"
    good "  # the reasoning is in TODO.md\n  MARKERS = /TODO|FIXME|XXX/\n"
    check do |src, path|
      # The lookahead keeps TODO.md, the repo-wide backlog, from reading as a
      # marker — see data/laws.yml `unfinished`, which learned this at :veto.
      #
      # A marker inside a regex literal is a detector, which is the reason this
      # rule already skips the directory it lives in — and detectors live outside
      # it too. Both of the tree's cases are that: personal_workspace greps a
      # MEMORY.md for the marker lines an operator left, history_valuables lists
      # the markers among the patterns worth recovering from git.
      scan_lines(without_regex_literals(src), /\b(TODO|FIXME|HACK|XXX)\b(?!\.md)/,
                 message: "unresolved marker - resolve or delete")
    end
  end
      end
    end
  end
end
