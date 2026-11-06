# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/css.rb:40 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: e1d4175512287fe8
require_relative "master/law/css"

Law.define(:MOBILE_FIRST) do
  source "Mobile First (Luke Wroblewski, 2011)"
  detect { |line| line.match?(/@media\s*\(\s*max-width/) }
  fix "Use min-width (mobile-first, progressive enhancement)."
  bad  "@media (max-width: 600px) {"
  good "@media (min-width: 600px) {"
end
