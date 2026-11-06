# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:950 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 6b4d41b053413f43
require_relative "master/law/universal"

Law.define(:FAIL_SAFE_DEFAULTS) do
  source "Saltzer & Schroeder - fail-safe defaults; OpenBSD default-deny policy"
  ask "Can missing, unreadable, malformed, stale or unmeasured policy state grant access, skip a safety check, or turn an error into success?"
  practice "Absence of proof is absence of permission. Unknown state fails closed for authority and fails visibly for correctness."
  fix "Default to denial; validate policy before applying it; treat missing or ambiguous state as BLOCKED/INCONCLUSIVE rather than success; and make recovery an explicit, bounded operation."
  bad <<~'X'
    allowed = rules[user] != false
  X
  good <<~'X'
    allowed = rules.fetch(user, false)
  X
end
