# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:1603 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: f2fd315ea25a9e5c
require_relative "master/law/universal"

Law.define(:NO_SELECTOR_ARGUMENTS) do
  source "Flag arguments / selector arguments"
  ask "Is an argument used mainly as a switch between distinct behaviors rather than as data?"
  fix "Expose distinct operations or strategy objects instead of hiding a dispatch behind a flag."
  bad <<~'X'
    save(record, mode: :json)
  X
  good <<~'X'
    JsonSaver.new.save(record)
  X
end
