# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml OPERATOR_RENDERED by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 77406de7c0ecfee3
require_relative "master/lib/master"

Law.define(:OPERATOR_RENDERED) do
  source "pub4 MASTER/data/laws.yml OPERATOR_RENDERED"
  practice "Rendered values are operator-owned. The system names the operator's choice; it never substitutes."
end
