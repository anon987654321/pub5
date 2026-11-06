# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/tools/rails/operator/model_contract_lint.rb by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 5fdb45068e477383
require_relative "master/lib/master"

Law.define(:LINT_MODEL_CONTRACT) do
  source "pub4 MASTER/tools/rails/operator/model_contract_lint.rb"
  practice "The model contract lint finds nothing above its baseline."
end
