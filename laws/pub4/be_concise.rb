# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/practice.rb:75 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 3532336f67cd1339
require_relative "master/law/practice"

Law.define(:BE_CONCISE) do
  source "MASTER constitution (soul.yml absolute.rules)"
  ask "Does this unit contain unnecessary verbosity in words, tokens, structure, or output?"
  # One rule, both halves: the catalogue's name is "avoid unnecessary words,
  # tokens, or lines", so the reply and the source are the same subject.
  practice <<~TEXT
    omit needless words and omit needless code. if the answer is one word, say
    one word.
  TEXT
  fix "Omit needless words. Omit needless code."
  bad  "a paragraph restating the question"
  good "one word"
end
