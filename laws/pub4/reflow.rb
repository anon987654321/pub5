# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml REFLOW by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 30994d923ef0cb9a
require_relative "master/lib/master"

Law.define(:REFLOW) do
  source "pub4 MASTER/data/laws.yml REFLOW"
  practice "Change line boundaries to follow structure, after structural edits."
end
