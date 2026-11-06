# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/lib/operator/ratchets.rb:390 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 98c149c825f55d7d
require_relative "master/lib/master"

Law.define(:RATCHET_NAME) do
  source "pub4 MASTER/lib/operator/ratchets.rb:390"
  practice "The count CLAUDE.md's \"two surfaces, no third\" asserts."
end
