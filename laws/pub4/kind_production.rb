# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml KIND_PRODUCTION by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 3cdb3273f66e6328
require_relative "master/lib/master"

Law.define(:KIND_PRODUCTION) do
  source "pub4 MASTER/data/laws.yml KIND_PRODUCTION"
  practice "A production file. A review on a finding is permanent until the operator re-reviews."
end
