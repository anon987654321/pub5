# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml KIND_GENERATOR by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: e72d5a9ffe0be787
require_relative "master/lib/master"

Law.define(:KIND_GENERATOR) do
  source "pub4 MASTER/data/laws.yml KIND_GENERATOR"
  practice "A code generator. A review on a finding expires in one year."
end
