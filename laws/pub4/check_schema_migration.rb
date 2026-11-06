# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/checks/checks.yml schema_migration by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: a17299b0a9e7666f
require_relative "master/lib/master"

Law.define(:CHECK_SCHEMA_MIGRATION) do
  source "pub4 MASTER/checks/checks.yml schema_migration"
  practice "Check schema_migration holds: Schema/migration check passed for apps Rails apps."
end
