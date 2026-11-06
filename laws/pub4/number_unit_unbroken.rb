# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/typesetting.rb:236 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 97351419dd4548d9
require_relative "master/law/typesetting"

module Law
  ::Law.define(:NUMBER_UNIT_UNBROKEN) do
    source "Bringhurst 2.4.6, link short numerical expressions with hard spaces; nb groups thousands with a space"
    tags %i[TYPOGRAPHY]
    path Regexp.union(C::PATH, Deploy::RenderedDesign::SNAPSHOT)
    example_path "/repo/RAILS/brgen/config/locales/nb.yml"
    fix "Join a number to its unit and its digit groups with U+00A0 (&nbsp; in ERB, delimiter U+00A0), " \
        "or set the price white-space: nowrap."
    bad C.locale_fixture("listing.distance", "%{km} km")
    good C.locale_fixture("listing.distance", "%{km}#{C.mark(:nbsp)}km")
    check { |src, path| C.unit_breaks(src, path).map { |hit| finding(**hit) } }
    snap = Deploy::RenderedDesign
    broken, joined = [2, 1].map { |tops| snap.fixture(numbers: [{ "text" => "1 299 kr", "tops" => tops }]) }
    adapter(:rendered_ui, languages: %i[json], example_path: snap::EXAMPLE, bad: broken, good: joined) do |text, file|
      snap.findings(:NUMBER_UNIT_UNBROKEN, text, file).map { |hit| finding(**hit) }
    end
  end
end
