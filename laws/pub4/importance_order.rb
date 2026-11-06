# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/practice.rb:473 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 317d9948c2e0b357
require_relative "master/law/practice"

Law.define(:IMPORTANCE_ORDER) do
  source "MASTER constitution (soul.yml absolute.rules)"
  practice <<~TEXT
    Inverted Pyramid (files) - public API first, primary logic next, helpers
    and constants last; see laws.yml style.line_order.
  TEXT
  fix "Inverted Pyramid (files) - public API first, primary logic next, helpers and constants last;"
  bad  "private helpers above the public API"
  good "public API first, helpers last"
end
