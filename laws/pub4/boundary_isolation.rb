# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:1331 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 5a50bc7b05fc823f
require_relative "master/law/universal"

Law.define(:BOUNDARY_ISOLATION) do
  source "Boundaries (Gary Bernhardt) / Clean Architecture"
  ask "Does third-party API or framework surface leak directly into core logic?"
  fix "Translate external contracts at a boundary and keep the core independent."
  bad <<~'X'
    status = Stripe::Charge.create(amount: cents).status
  X
  good <<~'X'
    status = Payments::Authorization.new(gateway: stripe).call(amount)
  X
end
