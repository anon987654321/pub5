# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:1379 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: a270d9e7b4905ecd
require_relative "master/law/universal"

Law.define(:DEFENSIVE_INPUT) do
  source "Defensive programming / safe boundaries"
  ask "Is external or untrusted input used without checking its shape, range, encoding, or allowed values?"
  fix "Validate or parse input at the boundary before it reaches trusted logic."
  bad <<~'X'
    File.read(params[:path])
  X
  good <<~'X'
    path = SafePath.parse(params.fetch(:path)); File.read(path)
  X
end
