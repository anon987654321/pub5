# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/lib/operator/ratchets.rb:508 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: ad701829b00143d3
require_relative "master/lib/master"

Law.define(:RATCHET_RAILS_LINT) do
  source "pub4 MASTER/lib/operator/ratchets.rb:508"
  practice "The rails lint ratchet never rises above its ceiling and never sits below it unlowered."
end
