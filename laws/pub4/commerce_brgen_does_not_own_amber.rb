# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/commerce.rb:14 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 6bfb0478147c5e30
require_relative "master/law/commerce"

Law.define(:COMMERCE_BRGEN_DOES_NOT_OWN_AMBER) do
  path "RAILS/brgen_marketplace/"
  source "pub4 commerce boundary - Amber owns wardrobe intelligence; BRGEN owns transactions"
  detect { |line| line.match?(/\b(?:TasteRanker|WardrobeGap|ShopTheLook|WardrobeItem)\b/) }
  fix "Keep wardrobe ranking and wardrobe records in Amber; expose only commerce references and catalog facts across the boundary."
  bad "TasteRanker.new(Current.user).rank(listings)"
  good "Marketplace::SearchRanker.new(listings, query: query, viewer: Current.user).relation"
end
