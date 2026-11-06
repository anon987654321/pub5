# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml REACH_skip_to_main by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: e2f1281596b69c63
require_relative "master/lib/master"

Law.define(:REACH_SKIP_TO_MAIN) do
  source "pub4 MASTER/data/laws.yml REACH_skip_to_main"
  practice "A layout that traps the keyboard before the main content."
end
