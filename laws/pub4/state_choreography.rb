# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/css.rb:233 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 3b9731cbf6cad77a
require_relative "master/law/css"

Law.define(:STATE_CHOREOGRAPHY) do
  path "RAILS/"
  source "Interaction feedback - loading, success and failure are observable states"
  ask "Does an action expose a coherent state sequence such as idle -> working -> success/failure, with the final state remaining understandable after motion stops? Do not rely on color, motion, or a short-lived flash as the only evidence."
  fix "Give each important action an explicit state, choreograph its transition with the shared motion tokens, and keep a static success or failure representation for reduced motion."
  bad "Tap Pay; briefly spin; disappear with no persistent result."
  good "Tap Pay -> working state -> self-drawing success mark or persistent failure state; all meanings remain available without motion."
end
