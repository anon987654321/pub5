# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/checks/checks.yml reflow by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: d8435d7ecd0af467
require_relative "master/lib/master"

Law.define(:CHECK_REFLOW) do
  source "pub4 MASTER/checks/checks.yml reflow"
  practice "Check reflow holds: ok: no overflow across the width sweep"
end
