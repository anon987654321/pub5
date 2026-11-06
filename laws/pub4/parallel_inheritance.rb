# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:1665 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 8c12edad07d5dfd4
require_relative "master/law/universal"

Law.define(:PARALLEL_INHERITANCE) do
  source "Refactoring - Parallel Inheritance Hierarchies (Fowler)"
  ask "Does adding a type in one hierarchy require adding a corresponding type in another hierarchy?"
  fix "Collapse the parallel hierarchies or compose the varying dimensions."
  bad <<~'X'
    JsonReport + JsonExporter; CsvReport + CsvExporter
  X
  good <<~'X'
    Report.new(formatter: JsonExporter.new)
  X
end
