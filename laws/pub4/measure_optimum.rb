# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/css.rb:31 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: c70cac40f406fa2e
require_relative "master/law/css"

Law.define(:MEASURE_OPTIMUM) do
  source "Bringhurst, Elements of Typographic Style - the measure (45-75 chars)"
  # A media query bound is a viewport question, not a text measure.
  detect { |line| !line.include?("@media") && line.match?(/max-width:\s*([89]\d{2}|\d{4,})px/) }
  fix "Bound running-text columns to ~66ch (≈ 33rem), not wide px values."
  bad  "article { max-width: 960px; }"
  good "article { max-width: 66ch; }"
end
