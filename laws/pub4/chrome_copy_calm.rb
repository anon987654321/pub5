# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/typesetting.rb:219 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 03abbced79725b03
require_relative "master/law/typesetting"

module Law
  ::Law.define(:CHROME_COPY_CALM) do
    source "Butterick, one exclamation mark is enough; Krug, happy talk must die; the operator's dmesg voice"
    tags %i[TYPOGRAPHY]
    path %r{/config/locales/[^/]+\.yml\z}
    example_path "/repo/RAILS/brgen/config/locales/nb.yml"
    fix "State the fact and end it with a full stop: \"Annonsen er publisert.\""
    bad C.locale_fixture("flash.created", "Annonsen er publisert!")
    good C.locale_fixture("flash.created", "Annonsen er publisert.")
    check do |src, path|
      chrome = ->(keys) { keys.intersect?(C::CHROME_KEYS) }
      loud = C.judge(src, path, chrome) do |text, _lang|
        "exclamation mark in interface copy - state the fact" if text.match?(/!(?!=)/)
      end
      loud.map { |hit| finding(**hit) }
    end
  end
end
