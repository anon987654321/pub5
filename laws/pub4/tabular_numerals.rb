# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/geometry.rb:68 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: b1077aa620c9d6e6
require_relative "master/law/geometry"

module Law
  ::Law.define(:TABULAR_NUMERALS) do
    GP.declare(self, :TABULAR_NUMERALS)
    path GP::G::SNAPSHOT
    source "Bringhurst 3.2.1 and Butterick: tabular figures where numbers align; worn_type.catalog.require_tabular_nums"
    fix "Set counts, prices, times and table columns with font-variant-numeric: tabular-nums."
    bad GP::G.fixture(tabular: [{ "sel" => "td.price", "numeric" => "normal" }])
    good GP::G.fixture(tabular: [{ "sel" => "td.price", "numeric" => "tabular-nums" }])
  end
end
