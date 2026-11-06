# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml SACRED_AUTHORSHIP_soul_hash_mismatch by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 47483b47e11d5d41
require_relative "master/lib/master"

Law.define(:SACRED_AUTHORSHIP_SOUL_HASH_MISMATCH) do
  source "pub4 MASTER/data/laws.yml SACRED_AUTHORSHIP_soul_hash_mismatch"
  practice "A soul.yml whose body_sha256 does not match the loaded soul.rb."
end
