# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:1770 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: f7c3c195530cdafd
require_relative "master/law/universal"

Law.define(:INCONCLUSIVE_IS_NOT_PASS) do
  source "MASTER constitutional capability-status policy"
  ask "Did an unavailable dependency, skipped probe, timeout, missing permission, or unmeasured check get treated as success?"
  practice "Unknown, skipped and unavailable are distinct from pass."
  fix "Return an explicit inconclusive/degraded result and preserve the unresolved evidence."
  bad "Browser unavailable, therefore visual check passed."
  good "Browser unavailable, visual check inconclusive, no completion claim."
end
