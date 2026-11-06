# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml ROBUSTNESS_bounded_operation_lifecycle by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 0a80f8a6b1f282ed
require_relative "master/lib/master"

Law.define(:ROBUSTNESS_BOUNDED_OPERATION_LIFECYCLE) do
  source "pub4 MASTER/data/laws.yml ROBUSTNESS_bounded_operation_lifecycle"
  practice "A timeout bounds the direct child but leaves owned descendants, inherited pipes, readers or cleanup unbounded."
end
