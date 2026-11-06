# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/lib/operator/ratchets.rb:118 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 0329327f81a88ba5
require_relative "master/lib/master"

Law.define(:RATCHET_MASTER_YAML) do
  source "pub4 MASTER/lib/operator/ratchets.rb:118"
  practice "Rules that reach no detector, and files that declare no namespace."
end
