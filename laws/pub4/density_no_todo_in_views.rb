# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml DENSITY_no_todo_in_views by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 7aebd11d473799e8
require_relative "master/lib/master"

Law.define(:DENSITY_NO_TODO_IN_VIEWS) do
  source "pub4 MASTER/data/laws.yml DENSITY_no_todo_in_views"
  practice "A TODO left in a view."
end
