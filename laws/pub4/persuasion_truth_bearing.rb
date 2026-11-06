# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml PERSUASION_truth_bearing by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 85b89e50dfe1702a
require_relative "master/lib/master"

Law.define(:PERSUASION_TRUTH_BEARING) do
  source "pub4 MASTER/data/laws.yml PERSUASION_truth_bearing"
  practice "Any scarcity, urgency, social proof, reference price or default shown to a user is computed from a source of truth in the database and remains true at render time. A persuasive element that requires a fact to be false, hidden, or louder than the fact it decorates fails this Law."
end
