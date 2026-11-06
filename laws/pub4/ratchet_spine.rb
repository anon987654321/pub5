# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/lib/operator/ratchets.rb:307 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 13fc4d37d62f3c3a
require_relative "master/lib/master"

Law.define(:RATCHET_SPINE) do
  source "pub4 MASTER/lib/operator/ratchets.rb:307"
  practice "The spine ratchet never rises above its ceiling and never sits below it unlowered."
end
