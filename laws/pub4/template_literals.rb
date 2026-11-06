# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/javascript.rb:75 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: fbfd5cd596782e07
require_relative "master/law/javascript"

Law.define(:TEMPLATE_LITERALS) do
  source "Airbnb JS Style Guide - template literals (ES6)"
  detect { |line| line.match?(/["']\s*\+\s*\w+\s*\+\s*["']/) }
  fix "Use `Hello ${name}!` template literals."
  bad  "'Hello ' + name + '!'"
  good "`Hello ${name}!`"
end
