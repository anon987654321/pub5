# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml RECOMMEND by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 1f81ac6951a0dc18
require_relative "master/lib/master"

Law.define(:RECOMMEND) do
  source "pub4 MASTER/data/laws.yml RECOMMEND"
  practice "When evidence is insufficient for a safe automatic change, recommend the smallest useful change instead of guessing."
end
