# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/html.rb:281 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 5f4a5572b0ed4143
require_relative "master/law/html"

Law.define(:PRESENTATIONAL_CLASS_NAME) do
  source "CSS naming - classes name meaning, not appearance"
  # The marker convention applies: a class whose word is a domain term rather
  # than a rendering decision ("seller center", the management area) states so
  # at the element instead of being renamed away from its own meaning.
  detect { |line| line.match?(/class=["'][^"']*\b(?:dim|muted|faded|bold|italic|underline|small|big|large|tiny|left|right|center|centre|red|green|blue|grey|gray|white|black)\b/) && !line.match?(/scan:\s*intentional\b/) }
  fix "Name the role, not the rendering - or use the element that already means it (small, strong, em, time)."
  bad  "<span class=\"dim\">posted just now</span>"
  good "<small>posted just now</small>"
end
