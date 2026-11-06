# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml RAILS_DOCTRINE_convention_over_configuration by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 41f827c9352c90cd
require_relative "master/lib/master"

Law.define(:RAILS_DOCTRINE_CONVENTION_OVER_CONFIGURATION) do
  source "pub4 MASTER/data/laws.yml RAILS_DOCTRINE_convention_over_configuration"
  practice "A configuration where a convention the reader already knows would serve."
end
