# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml KIND_FIXTURE by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: da49ae095718ea0c
require_relative "master/lib/master"

Law.define(:KIND_FIXTURE) do
  source "pub4 MASTER/data/laws.yml KIND_FIXTURE"
  practice "A fixture. A review on a finding expires in 90 days and returns if not re-accepted."
end
