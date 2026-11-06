# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml ROBUSTNESS_never_batch_delete by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 26fbc04a61ac4167
require_relative "master/lib/master"

Law.define(:ROBUSTNESS_NEVER_BATCH_DELETE) do
  source "pub4 MASTER/data/laws.yml ROBUSTNESS_never_batch_delete"
  practice "A glob that removes more than one file."
end
