# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml ROBUSTNESS_secret_proximity by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: c187b30cb5c21908
require_relative "master/lib/master"

Law.define(:ROBUSTNESS_SECRET_PROXIMITY) do
  source "pub4 MASTER/data/laws.yml ROBUSTNESS_secret_proximity"
  practice "A credential-shaped literal in source."
end
