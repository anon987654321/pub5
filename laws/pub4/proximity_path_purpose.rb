# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml PROXIMITY_path_purpose by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: c375ae75113591f8
require_relative "master/lib/master"

Law.define(:PROXIMITY_PATH_PURPOSE) do
  source "pub4 MASTER/data/laws.yml PROXIMITY_path_purpose"
  practice "A directory nobody owns."
end
