# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:1465 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: e99d3863778f1b55
require_relative "master/law/universal"

Law.define(:VISUAL_HIERARCHY) do
  source "Visual hierarchy - information scent, typographic scale, Gestalt grouping"
  ask "On the rendered surface, can a first-time reader distinguish the primary task/content, supporting information, and tertiary controls at a glance? Does visual emphasis follow the user's current goal rather than decoration or implementation convenience?"
  fix "Name the primary, secondary and tertiary elements for the task; use the existing type, spacing and contrast tokens to establish their order; verify the result in rendered screenshots at mobile and desktop widths without hiding required actions."
  bad "A product card gives its seller metadata, badge, price, title and purchase action equal size and contrast."
  good "A product title and price lead; seller metadata supports the choice; the purchase action is unmistakable and secondary actions remain quieter."
end
