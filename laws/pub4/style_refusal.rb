# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml STYLE_REFUSAL by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: ebe1deb420b3365f
require_relative "master/lib/master"

Law.define(:STYLE_REFUSAL) do
  source "pub4 MASTER/data/laws.yml STYLE_REFUSAL"
  practice "Negative-list constraints are evaluated before rendering; refusal reports the matched constraint and never masquerades as a generation failure."
end
