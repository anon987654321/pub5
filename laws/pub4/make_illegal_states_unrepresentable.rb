# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:1003 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: bafddc0d1c212d0a
require_relative "master/law/universal"

Law.define(:MAKE_ILLEGAL_STATES_UNREPRESENTABLE) do
  source "Yaron Minsky - make illegal states unrepresentable"
  ask "Can an invalid combination of fields or values be constructed at all, or must every caller remember a runtime check?"
  fix "Encode the invariant in the data shape, constructor, type, or boundary."
  bad <<~'X'
    User.new(role: :admin, active: false)
  X
  good <<~'X'
    ActiveAdmin.new
  X
end
