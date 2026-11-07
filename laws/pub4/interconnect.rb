# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/graph.rb:112 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 393c946957e9d926
require_relative "master/lib/master"

Law.define(:interconnect) do
  source "pub4 MASTER/law/graph.rb:112"
  practice "Phantom YAML key reads and orphan data keys"
end
