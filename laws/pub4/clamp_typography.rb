# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/css.rb:10 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 7303d06a8f50cda2
require_relative "master/law/css"

Law.define(:CLAMP_TYPOGRAPHY) do
  source "CSS fluid typography - clamp() (web.dev)"
  detect { |line| line.match?(/@media.*\{[^}]*font-size:/) }
  fix "Use font-size: clamp(1rem, 2.5vw, 1.5rem)."
  bad  "@media (min-width: 40em) { h1 { font-size: 2rem; } }"
  good "h1 { font-size: clamp(1.5rem, 2.5vw, 2.5rem); }"
end
