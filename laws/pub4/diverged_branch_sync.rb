# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/practice.rb:414 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 32c4e1762cf65edf
require_relative "master/law/practice"

Law.define(:DIVERGED_BRANCH_SYNC) do
  source "MASTER constitution (soul.yml absolute.rules)"
  practice <<~TEXT
    on a rejected push with overlapping commits, tag a backup, reset to
    origin, cherry-pick only the intended commits, and push. Prefer
    cherry-pick over rebasing mixed history; never force-push main.
  TEXT
  fix "on a rejected push with overlapping commits, tag a backup, reset to origin, cherry-pick only the intended comm"
  bad  "force-pushes main"
  good "tags, resets, cherry-picks the intended commits"
end
