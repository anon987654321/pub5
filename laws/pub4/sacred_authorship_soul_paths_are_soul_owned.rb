# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml SACRED_AUTHORSHIP_soul_paths_are_soul_owned by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: d763389c27914adb
require_relative "master/lib/master"

Law.define(:SACRED_AUTHORSHIP_SOUL_PATHS_ARE_SOUL_OWNED) do
  source "pub4 MASTER/data/laws.yml SACRED_AUTHORSHIP_soul_paths_are_soul_owned"
  practice "Protected paths are declared only by soul.yml#absolute.sacred_paths and cannot be shadowed by laws.yml, runtime metadata or a Ruby constant."
end
