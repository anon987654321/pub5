# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/commerce.rb:23 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 21a1235883be5f7b
require_relative "master/law/commerce"

Law.define(:COMMERCE_EXTERNAL_SOURCES_STAY_EXPLAINABLE) do
  path "RAILS/amber/app/services/"
  source "pub4 commerce protocol - external inventory must carry source and provenance"
  detect { |line| line.match?(/Suggestion\.new\((?![^\n]*(?:reasons|commerce_key))[^\n]*\bscore\b[^\n]*\)/) }
  fix "Use ShopTheLook::Suggestion with source, reasons, and commerce_key so a commercial recommendation is attributable and explainable."
  bad 'Suggestion.new(title, merchant, url, "remote", score)'
  good 'Suggestion.new(title, merchant, url, "brgen", score, reasons, commerce_key)'
end
