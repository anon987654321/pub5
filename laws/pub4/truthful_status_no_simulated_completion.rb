# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml TRUTHFUL_STATUS_no_simulated_completion by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: e96cb4efe80fe46d
require_relative "master/lib/master"

Law.define(:TRUTHFUL_STATUS_NO_SIMULATED_COMPLETION) do
  source "pub4 MASTER/data/laws.yml TRUTHFUL_STATUS_no_simulated_completion"
  practice "A statement that repository work, a file read, or a command completed without the corresponding evidence."
end
