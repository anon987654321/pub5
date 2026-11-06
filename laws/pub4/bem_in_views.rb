# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/html.rb:51 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 85b407958c3878c9
require_relative "master/law/html"

Law.define(:BEM_IN_VIEWS) do
  path "/app/views/"
  source "style.yml bare_tag_targeting - no BEM in ERB"
  detect { |line| line.match?(/class=["'][^"']*__[^"']*["']/) }
  fix "Target bare tags in SCSS; remove __block__element classes from ERB."
  bad  "<div class=\"card__title\">"
  good "<h2>"
end
