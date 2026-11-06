# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/lib/operator/ratchets.rb:164 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 2d9e71a69d83c5c7
require_relative "master/lib/master"

Law.define(:RATCHET_AUTOFIX) do
  source "pub4 MASTER/lib/operator/ratchets.rb:164"
  practice "The autofix ratchet never rises above its ceiling and never sits below it unlowered."
end
