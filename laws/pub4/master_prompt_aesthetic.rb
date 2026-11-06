# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/practice.rb:615 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 152aa69cfceabcff
require_relative "master/law/practice"

Law.define(:MASTER_PROMPT_AESTHETIC) do
  source "MASTER constitution (soul.yml absolute.rules)"
  ask "Does the interactive CLI prompt make the current working location and active conversation destination unambiguous while preserving Git state, phase and input token in the OpenBSD dmesg console style?"
  practice <<~TEXT
    The prompt names the checkout and governed tree when the working directory
    is inside pub4, then shows the current subdirectory, Git state, phase and
    shell token. On a long path, preserve the checkout/tree prefix and current
    leaf rather than truncating away where the operator is. Outside the checkout,
    use a home-relative or absolute path. Keep one bounded plain-text line;
    append-only factual unit0: events carry detail. Never depend on colour,
    badges or Starship/powerline segments to explain state.
  TEXT
  fix "Keep the checkout/tree, working directory and active destination legible in the one-line prompt; preserve location under truncation and leave detail to dmesg-style events."
  bad  "recolours the prompt line and adds badges"
  good "keeps the one-line prompt plain and emits a factual fix0: status when work changes state"
end
