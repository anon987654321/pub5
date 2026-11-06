# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 AGENT_RULES.md (pub4 session rules) - Hard rules by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 96eb3ba197714b8b
require_relative "master/lib/master"

Law.define(:AGENT_PROVE_EACH_FIX) do
  source "pub4 AGENT_RULES.md (pub4 session rules) - Hard rules"
  practice "- **Prove each fix.** Every fix needs a test that fails on origin's code and passes with your fix. Prove it by swapping origin's copy back in, watching the test fail, then restoring.\n  - Browser-only behaviour (JS or CSS) can now be proven with brgen's system tests (`bin/rails test:system`, used by bin/ci).\n  - Use them for JS rows in brgen, and in amber or bsdports if their setup allows. Read `RAILS/brgen/test/application_system_test_case.rb`.\n  - Don't skip a row only because it is JS. Skip it only if no test of any kind can prove it."
end
