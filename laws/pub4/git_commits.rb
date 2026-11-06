# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/practice.rb:403 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 101eb31958b2eab4
require_relative "master/law/practice"

Law.define(:GIT_COMMITS) do
  source "MASTER constitution (soul.yml absolute.rules)"
  practice <<~TEXT
    commit after every meaningful change and never batch unrelated work. One
    concern per commit where practical; imperative subjects.
  TEXT
  fix "commit after every meaningful change and never batch unrelated work."
  bad  "one commit spanning four concerns"
  good "one concern per commit"
end
