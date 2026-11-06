# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:504 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: bfbeb54b4707833d
require_relative "master/law/universal"

Law.define(:MONOLITH_FIRST) do
  source "MonolithFirst (Martin Fowler)"
  ask "Is this splitting a cohesive application into services before a concrete extraction boundary or operational need exists?"
  fix "Keep the feature in the application until extraction is clearly justified."
  bad <<~'X'
    PaymentsServiceClient.call(order)
  X
  good <<~'X'
    Payments::Charge.call(order)
  X
end
