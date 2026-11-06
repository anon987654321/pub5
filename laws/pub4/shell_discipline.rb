# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/practice.rb:391 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: fd07c2a162c44f96
require_relative "master/law/practice"

Law.define(:SHELL_DISCIPLINE) do
  source "MASTER constitution (soul.yml absolute.rules)"
  practice <<~TEXT
    no sed, awk, head, tail, find, wc, perl or python in agent shell
    calls or committed scripts; BSD variants break GNU idioms and this tree
    deploys to OpenBSD. Ruby, zsh builtins and the dedicated tools instead.
  TEXT
  fix "no sed, awk, head, tail, find, wc, perl or python in agent shell calls or committed scripts;"
  bad  "sed -i on OpenBSD"
  good "ruby -e rewriting the file"
end
