# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:1207 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: fcc87bd2411ffc4c
require_relative "master/law/universal"

Law.define(:POSTEL) do
  source "Postel's Law / Robustness Principle"
  ask "Does this boundary reject safely normalizable valid variation or emit unnecessarily strict structure that callers do not need?"
  fix "Normalize harmless variation at the boundary and keep emitted contracts deliberate."
  bad <<~'X'
    raise unless input == input.strip
  X
  good <<~'X'
    value = input.strip
  X
end
