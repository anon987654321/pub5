# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml RAILS_DOCTRINE_progress_over_stability by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 941f1163b7c6b068
require_relative "master/lib/master"

Law.define(:RAILS_DOCTRINE_PROGRESS_OVER_STABILITY) do
  source "pub4 MASTER/data/laws.yml RAILS_DOCTRINE_progress_over_stability"
  practice "A stability held at the cost of a progress the operator has not chosen."
end
