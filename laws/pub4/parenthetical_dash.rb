# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/typesetting.rb:182 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 769d5eaaaa3756da
require_relative "master/law/typesetting"

module Law
  ::Law.define(:PARENTHETICAL_DASH) do
    source "Bringhurst 5.2.1, spaced en dashes for asides; Butterick, no double hyphens; skatteetaten.no, tankestrek"
    tags %i[TYPOGRAPHY]
    path C::PATH
    example_path "/repo/RAILS/brgen/config/locales/nb.yml"
    fix "Set an aside with a spaced en dash (U+2013); a hyphen joins words and never stands for a dash."
    bad C.locale_fixture("takeaway.pickup", "Hent maten selv - eller bestill levering")
    good C.locale_fixture("takeaway.pickup", "Hent maten selv #{C.mark(:ndash)} eller bestill levering")
    check { |src, path| C.judge(src, path) { |text, lang| C.dash(text, lang) }.map { |hit| finding(**hit) } }
  end
end
