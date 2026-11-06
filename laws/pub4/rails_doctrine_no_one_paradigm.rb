# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml RAILS_DOCTRINE_no_one_paradigm by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: f3a7fa9d7dafc677
require_relative "master/lib/master"

Law.define(:RAILS_DOCTRINE_NO_ONE_PARADIGM) do
  source "pub4 MASTER/data/laws.yml RAILS_DOCTRINE_no_one_paradigm"
  practice "A paradigm enforced where the problem does not demand it."
end
