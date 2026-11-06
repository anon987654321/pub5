# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:1039 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 6c9a016f0dd6c74a
require_relative "master/law/universal"

Law.define(:COMPLEX_SYSTEMS_FAIL) do
  source "Richard Cook - How Complex Systems Fail; resilience engineering"
  ask "Does this path assume the happy case or rely on a single safeguard with no defined degraded mode?"
  fix "Define independent safeguards and a bounded degraded mode."
  bad <<~'X'
    result = primary.fetch!
  X
  good <<~'X'
    result = primary.fetch(timeout: 2) || fallback.fetch
  X
end
