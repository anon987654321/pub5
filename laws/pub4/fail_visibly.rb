# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:108 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 7eaa6eef62f2bb9a
require_relative "master/law/universal"

Law.define(:FAIL_VISIBLY) do
  source "Fail Fast (Jim Shore, IEEE Software 2004)"
  ask "Does this code swallow exceptions or fail silently instead of surfacing the error with useful context?"
  detect { |line| line.match?(/(?<![\w:.])rescue\s*$|(?<![\w:.])rescue\s+Exception\b/) }
  fix "Catch specific errors, log context, re-raise or return Result."
  bad "rescue Exception"
  good "rescue IOError => e"
end
