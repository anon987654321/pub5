# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:577 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 38f1967014fa625b
require_relative "master/law/universal"

Law.define(:NO_HIDDEN_GLOBAL_STATE) do
  source "Clean Code - avoid global mutable state (R.C. Martin)"
  ask "Are global variables or mutable class-level values shared across modules without explicit ownership?"
  fix "Inject configuration and state through explicit boundaries."
  bad <<~'X'
    $current_user = user
  X
  good <<~'X'
    Context.new(current_user: user)
  X
end
