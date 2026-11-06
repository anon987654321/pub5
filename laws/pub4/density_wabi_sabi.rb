# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml DENSITY_wabi_sabi by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 46e8fe141d5b0500
require_relative "master/lib/master"

Law.define(:DENSITY_WABI_SABI) do
  source "pub4 MASTER/data/laws.yml DENSITY_wabi_sabi"
  practice "Imperfection treated as failure."
end
