# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:467 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 229d10a77e9e8d5f
require_relative "master/law/universal"

Law.define(:INTEGRATED_SYSTEMS) do
  source "OpenBSD integrated base; Value Integrated Systems (Rails Doctrine, DHH)"
  ask "Does this split a cohesive, locally auditable system into packages or services without a real ownership, privilege, failure or scaling boundary; or merge independent products and trust domains that should remain distinct?"
  practice "Prefer a coherent integrated base with one accountable owner for each decision. Keep cohesive mechanisms together, but keep independent applications, identities, privilege domains and failure boundaries separate."
  fix "Integrate code when it removes version skew and hidden coordination; extract only at a concrete operational or trust boundary; preserve each product's own public contract and deployment authority."
  bad <<~'X'
    HTTP.post(service_url, payload)
  X
  good <<~'X'
    Orders::Checkout.call(order)
  X
end
