# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml TRUTHFUL_STATUS_silent_test_skip by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 9380fbd3086567d4
require_relative "master/lib/master"

Law.define(:TRUTHFUL_STATUS_SILENT_TEST_SKIP) do
  source "pub4 MASTER/data/laws.yml TRUTHFUL_STATUS_silent_test_skip"
  practice "A skipped test with no reason."
end
