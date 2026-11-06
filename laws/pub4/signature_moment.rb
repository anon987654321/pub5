# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/interface.rb:167 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 2b4cd53ddfea7cc7
require_relative "master/law/interface"

Law.define(:SIGNATURE_MOMENT) do
  path "RAILS/"
  source "Interaction design - distinctive, frequent, functional moments"
  ask "Does this product surface have one deliberately distinctive interaction that users encounter often, improves the task rather than merely decorating it, matches the product's character, and remains effortless and accessible? Return CLEAN when an existing interaction already serves this role."
  fix "Choose one existing high-frequency interaction and give it immediate, restrained, distinctive feedback. Do not invent a feature solely for delight, duplicate the pattern elsewhere, or make motion or haptics the only signal."
  bad "Add a decorative animation with no relationship to the user's action."
  good "Make one frequent action produce immediate visual state, optional tactile feedback, and a clear success or failure result."
end
