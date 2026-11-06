# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/typesetting.rb:171 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: bcccf7e463ebb868
require_relative "master/law/typesetting"

module Law
  ::Law.define(:QUOTES_BY_LOCALE) do
    source "Butterick, Practical Typography: curly quotes, apostrophes point down; regjeringen.no: guillemets in nb"
    tags %i[TYPOGRAPHY]
    path C::PATH
    example_path "/repo/RAILS/brgen/config/locales/nb.yml"
    fix "Set nb quotations in guillemets (curly singles inside), en in curly doubles, the apostrophe as U+2019."
    bad "nb:\n  search:\n    empty: 'Ingen treff for \"%{q}\"'\n"
    good C.locale_fixture("search.empty", "Ingen treff for #{C.mark(:laquo)}%{q}#{C.mark(:raquo)}")
    check { |src, path| C.judge(src, path) { |text, lang| C.quotes(text, lang) }.map { |hit| finding(**hit) } }
  end
end
