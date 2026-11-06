# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:1075 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 231f94232e86e55a
require_relative "master/law/universal"

Law.define(:GUARD_EXPENSIVE) do
  source "MASTER-native - guard expensive operations"
  ask "Does this file perform expensive operations without checking relevant preconditions or bounds?"
  fix "Check prerequisites, estimate cost, and bound the operation before executing it."
  bad <<~'X'
    API.delete_all
  X
  good <<~'X'
    records = API.list(limit: 100); records.each(&:delete)
  X
end
