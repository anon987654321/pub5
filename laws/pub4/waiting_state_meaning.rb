# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/interface.rb:185 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: d30eb916ad044863
require_relative "master/law/interface"

Law.define(:WAITING_STATE_MEANING) do
  path "RAILS/"
  source "Interaction status - useful feedback during dead time"
  ask "When a user is waiting for a meaningful result, does the surface identify what is happening or what is being prepared, rather than exposing only a generic spinner or unexplained motion? Keep the message brief, truthful, localised, and independent of animation."
  fix "Expose a short status label alongside the existing progress or skeleton state. Keep it accurate and persistent long enough to orient the user; never invent progress or use animation as the only meaning."
  bad "<div class=\"spinner\" aria-label=\"Loading\"></div>"
  good "<div aria-busy=\"true\"><span>Loading results...</span><div class=\"skeleton\" aria-hidden=\"true\"></div></div>"
end
