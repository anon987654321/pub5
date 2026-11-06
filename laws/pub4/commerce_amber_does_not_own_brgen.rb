# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/commerce.rb:5 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 8648d2f9753006f8
require_relative "master/law/commerce"

Law.define(:COMMERCE_AMBER_DOES_NOT_OWN_BRGEN) do
  path "RAILS/amber/"
  source "pub4 commerce boundary - BRGEN owns listings/orders; Amber owns wardrobe intelligence"
  detect { |line| line.match?(/\bMarketplace::(?:Listing|Order|Store)\b/) }
  fix "Consume the public Shared::Commerce/BRGEN catalog contract through BrgenCommerce; do not load BRGEN models."
  bad 'Marketplace::Order.where(payment_status: "paid")'
  good "BrgenCommerce.search(item: item, limit: 6)"
end
