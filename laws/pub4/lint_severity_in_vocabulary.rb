# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml LINT_SEVERITY_IN_VOCABULARY by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: ed829bfe3a489a6b
require_relative "master/lib/master"

Law.define(:LINT_SEVERITY_IN_VOCABULARY) do
  source "pub4 MASTER/data/laws.yml LINT_SEVERITY_IN_VOCABULARY"
  practice "Every severity is one of info, warning, error, critical, veto."
end
