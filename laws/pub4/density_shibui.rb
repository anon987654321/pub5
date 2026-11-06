# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml DENSITY_shibui by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 48a1ebb2a27697ad
require_relative "master/lib/master"

Law.define(:DENSITY_SHIBUI) do
  source "pub4 MASTER/data/laws.yml DENSITY_shibui"
  practice "Something added to be noticed."
end
