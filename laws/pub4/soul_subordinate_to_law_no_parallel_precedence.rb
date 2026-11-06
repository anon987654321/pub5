# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml SOUL_SUBORDINATE_TO_LAW_no_parallel_precedence by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 1010dfc36e9515a7
require_relative "master/lib/master"

Law.define(:SOUL_SUBORDINATE_TO_LAW_NO_PARALLEL_PRECEDENCE) do
  source "pub4 MASTER/data/laws.yml SOUL_SUBORDINATE_TO_LAW_no_parallel_precedence"
  practice "The Law catalogue, Ruby identity code or execution metadata declares a competing source-authority order instead of reading soul.yml#authority_order."
end
