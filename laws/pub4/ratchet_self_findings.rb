# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/lib/operator/ratchets.rb:237 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 4c887a5d7f17182c
require_relative "master/lib/master"

Law.define(:RATCHET_SELF_FINDINGS) do
  source "pub4 MASTER/lib/operator/ratchets.rb:237"
  practice "The row above read \"what our own rules find in our own trees\" and counted the law alone, so this second population counts the 145 rules the scanner builds: law_audit runs them over a sixth of the tree and measures blindness, and bin/operator check runs them over all four top-level trees and records nothing."
end
