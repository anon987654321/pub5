# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml TRUTHFUL_STATUS_transient_feedback by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 6f7309b35aa4da0f
require_relative "master/lib/master"

Law.define(:TRUTHFUL_STATUS_TRANSIENT_FEEDBACK) do
  source "pub4 MASTER/data/laws.yml TRUTHFUL_STATUS_transient_feedback"
  practice "A loading, success, or failure state that flashes away."
end
