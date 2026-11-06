# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/lib/operator/ratchets.rb:251 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: bf139e46f7947572
require_relative "master/lib/master"

Law.define(:RATCHET_REACH) do
  source "pub4 MASTER/lib/operator/ratchets.rb:251"
  practice "The reach ratchet never rises above its ceiling and never sits below it unlowered."
end
