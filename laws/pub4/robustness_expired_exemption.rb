# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml ROBUSTNESS_expired_exemption by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: fe5cbe42a9f74cb2
require_relative "master/lib/master"

Law.define(:ROBUSTNESS_EXPIRED_EXEMPTION) do
  source "pub4 MASTER/data/laws.yml ROBUSTNESS_expired_exemption"
  practice "A review resolution past its expiry still in force."
end
