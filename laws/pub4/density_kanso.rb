# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml DENSITY_kanso by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 10d6bbac6b42cf8f
require_relative "master/lib/master"

Law.define(:DENSITY_KANSO) do
  source "pub4 MASTER/data/laws.yml DENSITY_kanso"
  practice "Simplicity not achieved; clutter remains."
end
