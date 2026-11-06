# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml STRUNK_WHITE_definite_specific_concrete by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: b951eb0a4d0aec26
require_relative "master/lib/master"

Law.define(:STRUNK_WHITE_DEFINITE_SPECIFIC_CONCRETE) do
  source "pub4 MASTER/data/laws.yml STRUNK_WHITE_definite_specific_concrete"
  practice "An abstraction where a definite, specific, concrete word is available."
end
