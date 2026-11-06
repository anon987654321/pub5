# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml POLA_mental_models by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 31d9d423aabb0319
require_relative "master/lib/master"

Law.define(:POLA_MENTAL_MODELS) do
  source "pub4 MASTER/data/laws.yml POLA_mental_models"
  practice "The system behaves in a way the operator did not expect, and does not name which will change."
end
