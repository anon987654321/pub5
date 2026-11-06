# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/javascript.rb:67 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: c8832c955bf13e1b
require_relative "master/law/javascript"

Law.define(:OPTIONAL_CHAINING) do
  source "ECMAScript 2020 - optional chaining (?.)"
  detect { |line| line.match?(/(\w+)\s*&&\s*\1\.\w+/) }
  fix "Rewrite to obj?.foo?.bar"
  bad  "user && user.name"
  good "user?.name"
end
