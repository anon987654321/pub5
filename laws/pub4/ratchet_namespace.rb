# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/lib/operator/ratchets.rb:264 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 1204f42191cdea65
require_relative "master/lib/master"

Law.define(:RATCHET_NAMESPACE) do
  source "pub4 MASTER/lib/operator/ratchets.rb:264"
  practice "The namespace ratchet never rises above its ceiling and never sits below it unlowered."
end
