# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/typesetting.rb:204 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: be8246d75254a721
require_relative "master/law/typesetting"

module Law
  ::Law.define(:SINGLE_SENTENCE_SPACE) do
    source "Bringhurst 2.1.4; Butterick, one space between sentences, no multiple word spaces"
    tags %i[TYPOGRAPHY]
    # HTML collapses a run of spaces, so ERB text is out; locale values and Markdown keep theirs.
    path %r{(?:/config/locales/[^/]+\.yml|/docs/[^/]+\.md)\z}
    example_path "/repo/RAILS/brgen/config/locales/nb.yml"
    fix "One word space between sentences and words; align columns with a table, not spaces."
    bad C.locale_fixture("flash.saved", "Lagret.  Du kan lukke vinduet.")
    good C.locale_fixture("flash.saved", "Lagret. Du kan lukke vinduet.")
    check do |src, path|
      runs = C.judge(src, path) { |text, _lang| "#{text[/\S {2,}\S/].inspect} - one space" if text.match?(/\S {2,}\S/) }
      runs.map { |hit| finding(**hit) }
    end
  end
end
