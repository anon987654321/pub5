# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/typesetting.rb:193 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 4a3310da90c9f661
require_relative "master/law/typesetting"

module Law
  ::Law.define(:TRUE_SYMBOLS) do
    source "Butterick, use the proper symbols, not (c) or (tm); Bringhurst ch. 5, multiplication and minus signs"
    tags %i[TYPOGRAPHY]
    path C::PATH
    example_path "/repo/RAILS/brgen/config/locales/nb.yml"
    fix "Write U+00D7 for a dimension, U+2212 for a negative value, U+00A9, U+2122 and U+00AE for the marks."
    bad C.locale_fixture("listing.size", "120 x 60 cm")
    good C.locale_fixture("listing.size", "120 #{C.mark(:times)} 60 cm")
    check { |src, path| C.judge(src, path) { |text, _lang| C.symbol(text) }.map { |hit| finding(**hit) } }
  end
end
