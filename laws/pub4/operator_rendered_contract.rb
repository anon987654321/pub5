# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml OPERATOR_RENDERED_contract by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: c0773d1170cdd43c
require_relative "master/lib/master"

Law.define(:OPERATOR_RENDERED_CONTRACT) do
  source "pub4 MASTER/data/laws.yml OPERATOR_RENDERED_contract"
  practice "The visual identity contract: signal and stillness."
end
