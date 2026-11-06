# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/practice.rb:146 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: e787f432d473c329
require_relative "master/law/practice"

Law.define(:RTFM_FIRST) do
  source "MASTER constitution (soul.yml absolute.rules)"
  practice <<~TEXT
    read the man page or upstream reference docs before using any command,
    config file, framework, operating system, or programming language.
    Training-data assumptions about flags, syntax, and behavior are unreliable
    - verify against the source.
  TEXT
  fix "read the man page or upstream reference docs before using any command, config file, framework, operating syste"
  bad  "guesses the flag from memory"
  good "reads the man page on the box first"
end
