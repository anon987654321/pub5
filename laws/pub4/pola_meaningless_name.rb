# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml POLA_meaningless_name by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 8719936fa2afc299
require_relative "master/lib/master"

Law.define(:POLA_MEANINGLESS_NAME) do
  source "pub4 MASTER/data/laws.yml POLA_meaningless_name"
  practice "A name that does not state the present meaning of the thing."
end
