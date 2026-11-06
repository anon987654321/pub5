# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml REACH_aria_labels by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: fa96544b97934c11
require_relative "master/lib/master"

Law.define(:REACH_ARIA_LABELS) do
  source "pub4 MASTER/data/laws.yml REACH_aria_labels"
  practice "An interactive element with no accessible name."
end
