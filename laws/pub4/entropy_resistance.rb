# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:822 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: c437fde89976619e
require_relative "master/law/universal"

Law.define(:ENTROPY_RESISTANCE) do
  source "The Pragmatic Programmer - software entropy"
  ask "Is disorder accumulating through inconsistent names, exceptions, stale conventions, or abandoned paths?"
  fix "Remove drift and consolidate exceptions before they become a second system."
  bad <<~'X'
    foo_name = user_name; usr = account.name
  X
  good <<~'X'
    account_name = account.name
  X
end
