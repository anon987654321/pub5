# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:676 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 18c281e7f19c1e3d
require_relative "master/law/universal"

Law.define(:CHESTERTONS_FENCE) do
  source "Chesterton's Fence (G.K. Chesterton, 1929)"
  ask "Is existing code being removed or changed without first understanding why it exists?"
  fix "Read history, tests, callers, and rationale before removing it."
  bad <<~'X'
    delete_legacy_authentication
  X
  good <<~'X'
    git blame lib/authentication.rb
  X
end
