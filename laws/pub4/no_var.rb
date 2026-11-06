# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/javascript.rb:25 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: f58ac7af8343eb61
require_relative "master/law/javascript"

Law.define(:NO_VAR) do
  source "Airbnb JS Style Guide - no var (ES6 let/const)"
  # A declaration sits at a statement position: the start of a line, or straight
  # after a brace, a semicolon or an opening paren. \bvar\s+\w alone matched the
  # word anywhere, including inside a string — stt_endpointing.test.mjs carries
  # Norwegian speech fixtures, and "det var veldig hyggelig å høre" is the verb
  # "was", which this rule read as a variable declaration.
  detect { |line| line.match?(/(?:^|[{};(])\s*var\s+\w/) }
  fix "Use const (default) or let (when reassigned)."
  bad  "var x = 1;"
  # Both directions: a declaration is still caught after a brace, and the word
  # inside a sentence is not a declaration.
  good %(const x = 1;\nconst said = "det var veldig hyggelig";\n)
end
