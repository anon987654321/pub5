# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/tools/word_boundary_lint.rb by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 05bb9e5691bd9f26
require_relative "master/lib/master"

Law.define(:LINT_WORD_BOUNDARY) do
  source "pub4 MASTER/tools/word_boundary_lint.rb"
  practice "\\b next to punctuation has now cost this repo three incidents: the old backlog read as a work marker, and OPEN_CLOSED's is_a? clause which could never match."
end
