# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml BAYMARD_INLINE_VALIDATION_RECOVERY by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 44f020daaa7e96b4
require_relative "master/lib/master"

Law.define(:BAYMARD_INLINE_VALIDATION_RECOVERY) do
  source "pub4 MASTER/data/laws.yml BAYMARD_INLINE_VALIDATION_RECOVERY"
  practice "Form validation supports recovery: do not report an error before a user has had a reasonable chance to enter a value, identify the specific problem, clear or update feedback when corrected, and preserve unrelated valid input."
end
