# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml META_AUTHOR by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: ede14826f24ce79b
require_relative "master/lib/master"

Law.define(:META_AUTHOR) do
  source "pub4 MASTER/data/laws.yml META_AUTHOR"
  practice "The author of record, in whom authority vests."
end
