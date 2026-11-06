# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/checks/checks.yml state_matrix by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 54f2fe451a93ef67
require_relative "master/lib/master"

Law.define(:CHECK_STATE_MATRIX) do
  source "pub4 MASTER/checks/checks.yml state_matrix"
  practice "Check state_matrix holds: ok: declared component states render distinctly and inside their boxes"
end
