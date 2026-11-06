# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:774 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 3a0f5eac44076266
require_relative "master/law/universal"

Law.define(:GRACEFUL_BOUNDARIES) do
  source "Boundaries (Gary Bernhardt) - values at the edges"
  ask "Does a boundary assume perfect fidelity or that the other side will never change?"
  fix "Translate and validate at boundaries; define safe degradation."
  bad <<~'X'
    JSON.parse(remote_body).fetch("user")
  X
  good <<~'X'
    payload = JSON.parse(remote_body); UserPayload.parse(payload)
  X
end
