# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/geometry.rb:53 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 47f22753bed68016
require_relative "master/law/geometry"

module Law
  ::Law.define(:TYPEFACE_PER_ROLE) do
    GP.declare(self, :TYPEFACE_PER_ROLE)
    path Regexp.union(GP::G::SNAPSHOT, GP::SWISS_TREES)
    source "Vignelli, The Vignelli Canon: few typefaces, each with a role; operator 2026-10-11 and 2026-11-06"
    fix "Set UI and text in the one sans stack (var(--font)); monospace for chat, terminal and code. " \
        "BPLANS/ may use serifs."
    bad GP::G.fixture(elements: [GP::G.leaf("h1", font_family: "Georgia, serif")])
    good GP::G.fixture(elements: [GP::G.leaf("h1"), GP::G.leaf("pre.terminal", font_family: "Menlo, monospace")])
    adapter(:whole_file, languages: %i[css scss html], example_path: "/repo/RAILS/brgen/app/assets/stylesheets/_t.scss",
                         bad: "h1 { font-family: \"Iowan Old Style\", Georgia, serif; }\n",
                         good: "body { font-family: var(--font), sans-serif; }\n") do |src, file|
      GP.serif_rows(src, file).map { |hit| finding(**hit) }
    end
  end
end
