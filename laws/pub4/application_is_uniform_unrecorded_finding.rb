# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml APPLICATION_IS_UNIFORM_unrecorded_finding by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 623b585ac8f51103
require_relative "master/lib/master"

Law.define(:APPLICATION_IS_UNIFORM_UNRECORDED_FINDING) do
  source "pub4 MASTER/data/laws.yml APPLICATION_IS_UNIFORM_unrecorded_finding"
  practice "A finding made and not emitted."
end
