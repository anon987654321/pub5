# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/css.rb:379 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: d7a94b15a3729d3e
require_relative "master/law/css"

Law.define(:NO_ORDINAL_ORNAMENT) do
  source "LINEARITY - a 01, 02, 03 marker promises a sequence; on items with no order it is decoration"
  detect { |line| DesignMarks.ordinal_ornament?(line) }
  fix "Drop the number, or make the items an ordered list when the order is real."
  bad  ".card::before { content: counter(card, decimal-leading-zero); }"
  good "ol.steps li::marker { content: counter(list-item) \". \"; }"
end
