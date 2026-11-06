# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml APPLICATION_IS_UNIFORM_constitution_self_governed by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 1f4e31ae638903cb
require_relative "master/lib/master"

Law.define(:APPLICATION_IS_UNIFORM_CONSTITUTION_SELF_GOVERNED) do
  source "pub4 MASTER/data/laws.yml APPLICATION_IS_UNIFORM_constitution_self_governed"
  practice "The law catalogue or its validator is treated as exempt from the laws it declares."
end
