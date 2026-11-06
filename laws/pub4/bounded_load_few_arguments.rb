# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml BOUNDED_LOAD_few_arguments by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: dede99fd2e216be9
require_relative "master/lib/master"

Law.define(:BOUNDED_LOAD_FEW_ARGUMENTS) do
  source "pub4 MASTER/data/laws.yml BOUNDED_LOAD_few_arguments"
  practice "A method with more than three arguments."
end
