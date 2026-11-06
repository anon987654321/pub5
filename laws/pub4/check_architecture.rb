# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/checks/checks.yml architecture by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 88f4313c157a3378
require_relative "master/lib/master"

Law.define(:CHECK_ARCHITECTURE) do
  source "pub4 MASTER/checks/checks.yml architecture"
  practice "Check architecture holds: pub4 check architecture (architecture.rb)"
end
