# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml REMOVE by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: a0cba70116cfa9a3
require_relative "master/lib/master"

Law.define(:REMOVE) do
  source "pub4 MASTER/data/laws.yml REMOVE"
  practice "Delete only proven dead, redundant, historical, or transitional material."
end
