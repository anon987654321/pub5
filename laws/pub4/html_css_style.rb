# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/practice.rb:590 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 13b71352846bbfc4
require_relative "master/law/practice"

Law.define(:HTML_CSS_STYLE) do
  source "MASTER constitution (soul.yml absolute.rules)"
  practice <<~TEXT
    Semantic HTML - bare selectors (nav a, main, h1) over class soup; tag
    helpers over content_tag; omit class attributes unless brand, button or badge
    semantics require them. Structure carries meaning, classes are the last
    resort.
  TEXT
  fix "Semantic HTML - bare selectors (nav a, main, h1) over class soup;"
  bad  "div.nav-link-wrapper-inner"
  good "nav a"
end
