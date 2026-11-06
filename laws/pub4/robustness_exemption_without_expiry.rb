# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml ROBUSTNESS_exemption_without_expiry by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: cc62ce22c2b552f9
require_relative "master/lib/master"

Law.define(:ROBUSTNESS_EXEMPTION_WITHOUT_EXPIRY) do
  source "pub4 MASTER/data/laws.yml ROBUSTNESS_exemption_without_expiry"
  practice "A review resolution accepted with no expiry."
end
