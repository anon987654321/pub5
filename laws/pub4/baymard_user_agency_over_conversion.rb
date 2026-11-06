# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml BAYMARD_USER_AGENCY_OVER_CONVERSION by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 1bf07c64ac56781b
require_relative "master/lib/master"

Law.define(:BAYMARD_USER_AGENCY_OVER_CONVERSION) do
  source "pub4 MASTER/data/laws.yml BAYMARD_USER_AGENCY_OVER_CONVERSION"
  practice "A conversion gain is not acceptable when achieved through concealed costs, deceptive urgency, unnecessary forced account creation, preselected extras, obstructed refusal or cancellation, or misleading consent. Preserve a clear and usable path to decline, revise or leave."
end
