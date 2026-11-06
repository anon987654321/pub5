# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/geometry.rb:77 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 90fc310f9d1efdc4
require_relative "master/law/geometry"

module Law
  ::Law.define(:HEADING_WRAP_BALANCE) do
    GP.declare(self, :HEADING_WRAP_BALANCE)
    path GP::G::SNAPSHOT
    source "Bringhurst 2.4.8, no stray last word; CSS Text 4, text-wrap: balance"
    fix "Give h1-h3 text-wrap: balance (or pretty) so a heading never ends on one stray word."
    bad GP::G.fixture(elements: [GP::G.leaf("h1", text_lines: 2, text_wrap: "wrap")])
    good GP::G.fixture(elements: [GP::G.leaf("h1", text_lines: 2, text_wrap: "balance")])
  end
end
