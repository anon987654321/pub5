# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml ROBUSTNESS_unbounded_retry by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 8704e1ba143c5ee2
require_relative "master/lib/master"

Law.define(:ROBUSTNESS_UNBOUNDED_RETRY) do
  source "pub4 MASTER/data/laws.yml ROBUSTNESS_unbounded_retry"
  practice "A retry with no bound."
end
