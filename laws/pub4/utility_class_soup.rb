# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/html.rb:336 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 81eefcdd6db7a14c
require_relative "master/law/html"

Law.define(:UTILITY_CLASS_SOUP) do
  path "/app/views/"
  source "style.yml html.forbidden.framework_class_explosion"
  detect { |line| line.match?(/class=["'][^"']*(?:\b(?:mt|mb|ml|mr|px|py|col|row|d-flex|flex|grid|w-|h-)\b[^"']*){3,}[^"']*["']/i) }
  fix "Move layout to SCSS with bare tag targeting."
  bad  "<div class=\"row col mt mb\">"
  good "<div class=\"toolbar\">"
end
