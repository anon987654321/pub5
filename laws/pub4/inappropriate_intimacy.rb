# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:1439 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 8ac42ccdf2f92151
require_relative "master/law/universal"

Law.define(:INAPPROPRIATE_INTIMACY) do
  source "Refactoring - Inappropriate Intimacy (Fowler)"
  ask "Does one class access another class's internals instead of using its public contract?"
  fix "Expose the needed behavior through the owner's interface."
  bad <<~'X'
    user.instance_variable_get(:@roles).include?(:admin)
  X
  good <<~'X'
    user.admin?
  X
end
