# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml RAILS_DOCTRINE_optimize_for_programmer_happiness by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: fdb833f4e2db1aa3
require_relative "master/lib/master"

Law.define(:RAILS_DOCTRINE_OPTIMIZE_FOR_PROGRAMMER_HAPPINESS) do
  source "pub4 MASTER/data/laws.yml RAILS_DOCTRINE_optimize_for_programmer_happiness"
  practice "A design choice that makes the programmer less happy for the machine's benefit, without measured justification."
end
