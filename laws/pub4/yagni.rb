# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml YAGNI by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: d9b0e3e7cdf9c32b
require_relative "master/lib/master"

Law.define(:YAGNI) do
  source "pub4 MASTER/data/laws.yml YAGNI"
  practice "You Aren't Gonna Need It. Build only what the current requirement demands. An unused feature is not an investment; it is code that will drift, mislead a reader, and cost more to remove than it saved to write."
  ask "Trace each changed abstraction, option, feature, configuration key, dependency, and extension point to a current user requirement or executable contract. Identify speculative branches that no current caller or contract exercises. Distinguish necessary preparation for a demonstrated failure mode from future-proofing without evidence. Pass only when every unit has a current sponsor; fail with exact unused/superfluous units and the simpler alternative."
end
