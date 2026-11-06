# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/css.rb:56 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: a7f8742ab567f0d3
require_relative "master/law/css"

Law.define(:NO_LONG_TRANSITION) do
  source "style.yml motion budget / FrontendLawSet MOTION"
  detect { |line| line.match?(/transition(?:-duration)?\s*:[^;]*?\b(?:[4-9]\d\d|\d{4,})\s*ms/i) }
  fix "Keep transitions <=300ms."
  bad  ".card { transition: opacity 500ms var(--ease-out); }"
  good ".card { transition: opacity var(--transition-fast) var(--ease-out); }"
end
