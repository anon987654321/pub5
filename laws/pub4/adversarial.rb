# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/semantic.rb:166 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: ccaa8399fab457a0
require_relative "master/lib/master"

Law.define(:adversarial) do
  source "pub4 MASTER/law/semantic.rb:166"
  practice "Red-team scan: steelman then challenge - suppresses false positives"
end
