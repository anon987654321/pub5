# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/tools/rails/operator/fallback_drift_lint.rb by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 7f524f8f23443b2a
require_relative "master/lib/master"

Law.define(:LINT_FALLBACK_DRIFT) do
  source "pub4 MASTER/tools/rails/operator/fallback_drift_lint.rb"
  practice "The fallback drift lint finds nothing above its baseline."
end
