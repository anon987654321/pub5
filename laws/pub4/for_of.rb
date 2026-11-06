# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/javascript.rb:17 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 3dbe66cfe4ad29e3
require_relative "master/law/javascript"

Law.define(:FOR_OF) do
  source "Airbnb JS Style Guide - for...of over for...in"
  detect { |line| line.match?(/for\s*\(\s*(const|let|var)\s+\w+\s+in\s+/) }
  fix "for...in iterates prototype properties. Use for...of."
  bad  "for (const k in list) {"
  good "for (const k of list) {"
end
