# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml ROBUSTNESS_fail_safe_defaults by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: b016e545674865b4
require_relative "master/lib/master"

Law.define(:ROBUSTNESS_FAIL_SAFE_DEFAULTS) do
  source "pub4 MASTER/data/laws.yml ROBUSTNESS_fail_safe_defaults"
  practice "A default that fails open."
end
