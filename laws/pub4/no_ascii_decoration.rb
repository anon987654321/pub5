# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/practice.rb:451 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: ca3be1e94228b564
require_relative "master/law/practice"

Law.define(:NO_ASCII_DECORATION) do
  source "MASTER constitution (soul.yml absolute.rules)"
  practice <<~TEXT
    Strunk & White - no box-drawing or === / ### banners in code, comments,
    docs, or CLI; content is the separator.
  TEXT
  fix "Strunk & White - no box-drawing or === / ### banners in code, comments, docs, or CLI;"
  bad  "=== SECTION ==="
  good "the section's first sentence"
end
