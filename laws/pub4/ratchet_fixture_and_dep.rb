# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/lib/operator/ratchets.rb:213 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 514333011d982bb8
require_relative "master/lib/master"

Law.define(:RATCHET_FIXTURE_AND_DEP) do
  source "pub4 MASTER/lib/operator/ratchets.rb:213"
  practice "The fourth hygiene check and the dep graph both reported a number that nothing failed on."
end
