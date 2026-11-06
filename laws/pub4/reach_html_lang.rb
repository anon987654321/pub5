# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml REACH_html_lang by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 11e6e33e1d934a33
require_relative "master/lib/master"

Law.define(:REACH_HTML_LANG) do
  source "pub4 MASTER/data/laws.yml REACH_html_lang"
  practice "An HTML document with no language declared."
end
