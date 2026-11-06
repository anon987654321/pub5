# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml APPLICATION_IS_UNIFORM by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 2abd71dd0cbc99cd
require_relative "master/lib/master"

Law.define(:APPLICATION_IS_UNIFORM) do
  source "pub4 MASTER/data/laws.yml APPLICATION_IS_UNIFORM"
  practice "Every file passes through every law in both modalities. There is no path that skips a law. There is no file exempt by location. A file's kind is a fact, recorded; a finding is made against the fact, not against a bypass."
end
