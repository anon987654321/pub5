# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:1231 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 631e332566a41197
require_relative "master/law/universal"

Law.define(:TEMPORAL_COUPLING) do
  source "The Pragmatic Programmer - temporal coupling"
  ask "Must callers invoke methods in a specific order without the API enforcing that sequence?"
  fix "Encode required state transitions or provide one operation representing the valid sequence."
  bad <<~'X'
    client.fetch; client.authenticate
  X
  good <<~'X'
    client = Client.authenticated; client.fetch
  X
end
