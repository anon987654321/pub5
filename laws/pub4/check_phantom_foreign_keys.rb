# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/checks/checks.yml phantom_foreign_keys by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 169ed7766759582d
require_relative "master/lib/master"

Law.define(:CHECK_PHANTOM_FOREIGN_KEYS) do
  source "pub4 MASTER/checks/checks.yml phantom_foreign_keys"
  practice "Check phantom_foreign_keys holds: phantom_foreign_keys: clean (schemas schemas)"
end
