# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml KIND_BASE_MAINTENANCE by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: f3d005ed2ae58dbd
require_relative "master/lib/master"

Law.define(:KIND_BASE_MAINTENANCE) do
  source "pub4 MASTER/data/laws.yml KIND_BASE_MAINTENANCE"
  practice "A script sourced into the base system's maintenance. A review expires in one year."
end
