# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml ROBUSTNESS_unsafe_calls by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 34a674085b5b9f06
require_relative "master/lib/master"

Law.define(:ROBUSTNESS_UNSAFE_CALLS) do
  source "pub4 MASTER/data/laws.yml ROBUSTNESS_unsafe_calls"
  practice "Interpolation reaching shell command text."
end
