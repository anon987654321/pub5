# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 AGENT_RULES.md (pub4 session rules) - Hard rules by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: f313a177b223139a
require_relative "master/lib/master"

Law.define(:AGENT_WORK_IN_A_CLEAN_EXPORT) do
  source "pub4 AGENT_RULES.md (pub4 session rules) - Hard rules"
  practice "- **Work in a clean export of origin, not the working tree.** For example: `rm -rf $S/<name> && mkdir $S/<name> && git archive origin/main | tar -x -C $S/<name>`.\n  - Copy built CSS from the working tree (`RAILS/<app>/app/assets/builds/`) into the export, or render tests fail on application.css.\n  - Copy dev sqlite DBs if a tool needs `rails routes`.\n  - Re-export when origin moves.\n  - Helpers in $S (read them first): prove_app.rb, ot.rb, lint_ob.rb, loc_ob.rb, sync_ob.rb, mrt.rb (mrdamascy runner)."
end
