# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/project_context.yml operator_design_decisions_2026_11_06 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 85392d64cdc82a9b
require_relative "master/lib/master"

Law.define(:OPERATOR_DESIGN_DECISIONS_2026_11_06) do
  source "pub4 MASTER/data/project_context.yml operator_design_decisions_2026_11_06"
  practice "Contrast at least 4.5:1, 7:1 for body text. Page h1 uses the shared_chrome\nscale in tokens.yml. Small labels or kickers above headings are banned\n(NO_EYEBROW_LABEL). amber's pastels become amber's own colour scheme as\ntokens. The header band is light everywhere except in dark mode. The TV\naccent moves away from the danger red. brgen's AI entry shows \"1\" in the\nnav counter pill, as if a message were waiting, instead of \"new!\".\nReference products for principles only, never their look: x.com and\nreddit for the feed, bol.com for the marketplace, whyp.it for radio.\nBPLANS/ may use classic serif typography such as Garamond."
end
