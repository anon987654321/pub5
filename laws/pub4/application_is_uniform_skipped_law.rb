# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml APPLICATION_IS_UNIFORM_skipped_law by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: b52888107255ac18
require_relative "master/lib/master"

Law.define(:APPLICATION_IS_UNIFORM_SKIPPED_LAW) do
  source "pub4 MASTER/data/laws.yml APPLICATION_IS_UNIFORM_skipped_law"
  practice "A file passed through without one of the laws."
end
