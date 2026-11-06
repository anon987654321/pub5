# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:1367 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 57290a6b15736ec9
require_relative "master/law/universal"

Law.define(:IDEMPOTENT) do
  source "REST / distributed systems idempotency"
  ask "Would repeating the same operation with the same intended input produce an unintended different result?"
  fix "Make repeat calls converge to the same state or use an idempotency key."
  bad <<~'X'
    POST /payments creates another charge every retry
  X
  good <<~'X'
    PUT /payments/123 with idempotency key
  X
end
