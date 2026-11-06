# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml VISUAL_ALT_TEXT_PRESENT by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 1369effdc1e9c905
require_relative "master/lib/master"

Law.define(:VISUAL_ALT_TEXT_PRESENT) do
  source "pub4 MASTER/data/laws.yml VISUAL_ALT_TEXT_PRESENT"
  practice "Every image in an ad creative has non-empty alternative text unless it is explicitly decorative."
end
