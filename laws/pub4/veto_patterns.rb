# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/veto.rb:57 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 36b817b03549cbb3
require_relative "master/lib/master"

Law.define(:VETO_PATTERNS) do
  source "pub4 MASTER/law/veto.rb:57"
  practice "Unconditional merge blockers from laws.yml veto_patterns"
end
