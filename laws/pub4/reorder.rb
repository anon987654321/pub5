# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml REORDER by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 46e4fa3df40d62d1
require_relative "master/lib/master"

Law.define(:REORDER) do
  source "pub4 MASTER/data/laws.yml REORDER"
  practice "Put primary facts before secondary detail and exceptions."
end
