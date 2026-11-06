# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/interface.rb:176 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 2659372003ec10a5
require_relative "master/law/interface"

Law.define(:DIRECT_MANIPULATION_FEEDBACK) do
  path "RAILS/"
  source "Direct manipulation - immediate perceptual feedback"
  ask "When a user directly presses, drags, swipes, or dismisses something, does the interface acknowledge that input immediately rather than waiting for a delayed release or network result? Check pointer, keyboard, touch, visual state, and failure recovery together."
  fix "Respond at input start with a small state change, keep the gesture tied to the pointer while it moves, and retain a non-motion keyboard equivalent. Do not make the early feedback imply success before the action is actually committed."
  bad "click -> request -> finally show any indication that the press happened"
  good "pointerdown/active -> immediate press state; commit -> explicit success or failure state"
end
