# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:395 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: d91cd92b16246e5a
require_relative "master/law/universal"

Law.define(:CONVENTION_OVER_CONFIG) do
  source "Convention over Configuration (Rails Doctrine, DHH)"
  ask "Does this require explicit configuration where an established local convention already provides the correct behavior?"
  fix "Use the existing convention; add configuration only when it changes a real requirement."
  bad <<~'X'
    config = { adapter: :default }
  X
  good <<~'X'
    adapter = default_adapter
  X
end
