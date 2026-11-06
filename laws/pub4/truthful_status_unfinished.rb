# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml TRUTHFUL_STATUS_unfinished by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: e113113865e120ee
require_relative "master/lib/master"

Law.define(:TRUTHFUL_STATUS_UNFINISHED) do
  source "pub4 MASTER/data/laws.yml TRUTHFUL_STATUS_unfinished"
  practice "A TODO or FIXME in a comment, or an ellipsis body standing alone."
end
