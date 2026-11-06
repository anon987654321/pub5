# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml LINT_SOUL_PRINT_MATCHES_SOURCE by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 6e35ee09f19dc636
require_relative "master/lib/master"

Law.define(:LINT_SOUL_PRINT_MATCHES_SOURCE) do
  source "pub4 MASTER/data/laws.yml LINT_SOUL_PRINT_MATCHES_SOURCE"
  practice "data/soul.yml body_sha256 equals Soul.print body_sha256 for the loaded soul.rb."
end
