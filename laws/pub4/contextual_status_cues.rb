# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:1473 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 9c7acd232c4f4951
require_relative "master/law/universal"

Law.define(:CONTEXTUAL_STATUS_CUES) do
  source "Visibility of system status - contextual, persistent, actionable feedback"
  ask "At the point a user must decide or wait, does the interface explain the relevant state, what changed, and what action is available next? Is essential meaning retained after transient motion or color feedback ends?"
  fix "Show truthful status beside the affected task; use persistent text or semantics for success and failure, announce important asynchronous updates accessibly, and provide a concrete recovery action when one exists."
  bad "A save button spins briefly, returns to its idle appearance, and leaves the user unsure whether the save succeeded."
  good "The save action reports progress, then a persistent saved state; a failure explains the problem and offers a relevant retry path."
end
