# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml SINGULARITY_LAW_POLICY_HAS_ONE_OWNER by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 46b081b603ab2750
require_relative "master/lib/master"

Law.define(:SINGULARITY_LAW_POLICY_HAS_ONE_OWNER) do
  source "pub4 MASTER/data/laws.yml SINGULARITY_LAW_POLICY_HAS_ONE_OWNER"
  practice "Per-Law severity, mode, lifecycle, autofix and reach metadata has one owner in laws.yml#law_catalogue; runtime configuration must not duplicate that policy."
end
