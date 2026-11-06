# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/javascript.rb:4 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: ddab6949b98962a2
require_relative "master/law/javascript"

Law.define(:ASYNC_AWAIT) do
  source "ECMAScript 2017 - async/await over raw promises"
  detect { |line| line.match?(/\.then\(.*\.then\(.*\.then\(/) }
  fix "Use async/await for readability."
  bad  "a().then(b).then(c).then(d)"
  good "await a(); await b();"
end
