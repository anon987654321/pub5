# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:1219 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 206df4377e4c7ca0
require_relative "master/law/universal"

Law.define(:HYRUM) do
  source "Hyrum's Law"
  ask "Is a change removing or altering behavior that callers may already depend on despite it never being formally documented?"
  fix "Search actual consumers and observed behavior before changing the contract; preserve or version what is relied upon."
  bad <<~'X'
    Logger.write("ok") # side effect removed as "unused"
  X
  good <<~'X'
    Logger.write("ok") # callers depend on audit output
  X
end
