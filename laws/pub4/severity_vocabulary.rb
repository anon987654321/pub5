# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml SEVERITY_VOCABULARY by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 5db29a5fe1464366
require_relative "master/lib/master"

Law.define(:SEVERITY_VOCABULARY) do
  source "pub4 MASTER/data/laws.yml SEVERITY_VOCABULARY"
  practice "Every severity is one of these five. warn is a typo, not a synonym."
end
