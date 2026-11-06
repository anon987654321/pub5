# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml LINT_EVERY_LAW_HAS_ROOT_OR_NODE by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 468366690ef47fee
require_relative "master/lib/master"

Law.define(:LINT_EVERY_LAW_HAS_ROOT_OR_NODE) do
  source "pub4 MASTER/data/laws.yml LINT_EVERY_LAW_HAS_ROOT_OR_NODE"
  practice "Every top-level law names either a soul node or a root; every child inherits from its parent."
end
