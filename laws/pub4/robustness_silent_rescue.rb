# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml ROBUSTNESS_silent_rescue by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 13638ce91043ad62
require_relative "master/lib/master"

Law.define(:ROBUSTNESS_SILENT_RESCUE) do
  source "pub4 MASTER/data/laws.yml ROBUSTNESS_silent_rescue"
  practice "A rescue with no body."
end
