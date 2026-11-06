# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml KIND_MIGRATION by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 489b8a4ef463a1d9
require_relative "master/lib/master"

Law.define(:KIND_MIGRATION) do
  source "pub4 MASTER/data/laws.yml KIND_MIGRATION"
  practice "A database migration. A review on a finding expires in one year."
end
