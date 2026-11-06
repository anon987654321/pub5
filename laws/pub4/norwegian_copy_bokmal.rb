# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/brand.rb:67 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 10a33a821aea0b7c
require_relative "master/law/brand"

Law.define(:NORWEGIAN_COPY_BOKMAL) do
  source "Bergen brand systems - user-facing copy in Norwegian bokmål (snl.no orthography)"
  detect { |line| line.match?(/(?:placeholder|title|description|alt)="[^"]*\b(?:the|and|with|your)\b[^"]*"/i) }
  fix "Write user-facing strings in Norwegian bokmål; å/ø/æ, snl.no orthography."
  bad  'alt="Red cabin by the fjord at dusk"'
  good 'alt="Rødt trehus ved fjorden i kveldslys"'
end
