# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml RATCHET_DEPS_UNGRAPHED by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: c0514bd27db86524
require_relative "master/lib/master"

Law.define(:RATCHET_DEPS_UNGRAPHED) do
  source "pub4 MASTER/data/laws.yml RATCHET_DEPS_UNGRAPHED"
  practice "after: ids that do not resolve to a registered law."
end
