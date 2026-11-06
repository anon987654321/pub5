# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml STRUNK_WHITE_positive_form by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: ce4415e4d6f827ee
require_relative "master/lib/master"

Law.define(:STRUNK_WHITE_POSITIVE_FORM) do
  source "pub4 MASTER/data/laws.yml STRUNK_WHITE_positive_form"
  practice "A negation where an affirmation states the same thing more directly."
end
