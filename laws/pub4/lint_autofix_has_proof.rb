# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml LINT_AUTOFIX_HAS_PROOF by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 124684acde6a1c8e
require_relative "master/lib/master"

Law.define(:LINT_AUTOFIX_HAS_PROOF) do
  source "pub4 MASTER/data/laws.yml LINT_AUTOFIX_HAS_PROOF"
  practice "resolution automatic names a proof fixture that fails before and passes after."
end
