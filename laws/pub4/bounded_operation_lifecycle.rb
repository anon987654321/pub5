# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:925 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 15ec68f40d08ad3a
require_relative "master/law/universal"

Law.define(:BOUNDED_OPERATION_LIFECYCLE) do
  source "OpenBSD process discipline; bounded-deadline engineering"
  ask "Does the deadline cover the entire operation it owns, including child processes, inherited pipes, output readers and cleanup, or only the first wait?"
  practice "A timeout ends the whole owned operation, not merely its direct child."
  fix "Use one monotonic deadline across every wait; terminate the owned process group and stop its readers on expiry; preserve TIMEOUT as the result."
  bad <<~'X'
    waiter.join(timeout)
    reader.join
  X
  good <<~'X'
    deadline = monotonic + timeout
    waiter.join([deadline - monotonic, 0].max)
    reader.join([deadline - monotonic, 0].max)
  X
end
