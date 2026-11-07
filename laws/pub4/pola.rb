# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml POLA by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: b0d2dd49a2a763dc
require_relative "master/lib/master"

Law.define(:POLA) do
  source "pub4 MASTER/data/laws.yml POLA"
  practice "Principle of Least Astonishment. A system behaves the way a person who has not read the source will expect. If a necessary feature astonishes, redesign the feature rather than document the surprise."
  ask "For each user-visible workflow, predict what a reasonable first-time user expects from labels, controls, sequence, defaults, side effects, errors and reversibility. Compare those expectations with actual source/runtime evidence and screenshots or interaction traces. Identify hidden behaviour, surprising state changes, inconsistent conventions and undocumented dependencies. Abstain without user-flow evidence for rendered claims."
end
