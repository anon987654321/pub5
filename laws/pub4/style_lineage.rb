# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml STYLE_LINEAGE by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 005d903e9f62f614
require_relative "master/lib/master"

Law.define(:STYLE_LINEAGE) do
  source "pub4 MASTER/data/laws.yml STYLE_LINEAGE"
  practice "Style manifests separate inputs used from measured output influence; lineage alone never proves influence, and null influence requires a reason."
end
