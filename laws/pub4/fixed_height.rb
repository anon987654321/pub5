# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/css.rb:130 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: dd7b50418e6e7c61
require_relative "master/law/css"

Law.define(:FIXED_HEIGHT) do
  source "Every Layout (Bell & Pickering) - the content sizes the box"
  # A drawn stage — an art frame, a product-photo crop window — sizes itself
  # by contract, not by its content. Those lines carry scan: intentional with
  # the reason; the marker keeps the law on flowing-content boxes.
  detect { |line| line.match?(/(?<![a-z-])height:\s*[1-9]\d{2,}px/) && !line.match?(/scan:\s*intentional\b/) }
  fix "Use min-height for a floor, or let the content size the box."
  bad  ".card { height: 300px; }"
  good ".card { min-height: 300px; }"
end
