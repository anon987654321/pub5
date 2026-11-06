# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml RAILS_DOCTRINE by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: fa31f063a0b176d9
require_relative "master/lib/master"

Law.define(:RAILS_DOCTRINE) do
  source "pub4 MASTER/data/laws.yml RAILS_DOCTRINE"
  practice "The Rails Doctrine. A framework's posture toward its programmer is a design decision, and Rails chose: optimize for programmer happiness, trust convention over configuration, and treat the whole stack as one integrated system rather than a bag of parts."
end
