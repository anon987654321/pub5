# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml APPLICATION_IS_UNIFORM_legacy_reach_is_not_global by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 50c9a2769cc8ef03
require_relative "master/lib/master"

Law.define(:APPLICATION_IS_UNIFORM_LEGACY_REACH_IS_NOT_GLOBAL) do
  source "pub4 MASTER/data/laws.yml APPLICATION_IS_UNIFORM_legacy_reach_is_not_global"
  practice "Per-Law language, surface and path reach is sourced only from law_catalogue; an unscoped Law inherits the catalogue's universal-by-default policy."
end
