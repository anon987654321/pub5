# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/practice.rb:553 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 3c4e211b2ad75d86
require_relative "master/law/practice"

Law.define(:STRUNK_WHITE) do
  source "MASTER constitution (soul.yml absolute.rules)"
  practice <<~TEXT
    Strunk & White - active voice, needless words omitted, concrete nouns and
    verbs, one idea per sentence. Sentence case in prose, comments, logs and
    CLI; snake_case in code. No banners or bracket tags: ok: and warn:
    prefixes instead.
  TEXT
  fix "Strunk & White - active voice, needless words omitted, concrete nouns and verbs, one idea per sentence."
  bad  "the file was modified by the job"
  good "the job modified the file"
end
