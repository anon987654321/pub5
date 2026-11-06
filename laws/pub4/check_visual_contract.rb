# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/checks/checks.yml visual_contract by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: a17ade76ad07d12c
require_relative "master/lib/master"

Law.define(:CHECK_VISUAL_CONTRACT) do
  source "pub4 MASTER/checks/checks.yml visual_contract"
  practice "Check visual_contract holds: pub4 check visual_contract (visual_contract.rb)"
end
