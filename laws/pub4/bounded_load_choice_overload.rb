# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml BOUNDED_LOAD_choice_overload by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 9180d2ba14f39261
require_relative "master/lib/master"

Law.define(:BOUNDED_LOAD_CHOICE_OVERLOAD) do
  source "pub4 MASTER/data/laws.yml BOUNDED_LOAD_choice_overload"
  practice "More choices than the reader can decide between."
end
