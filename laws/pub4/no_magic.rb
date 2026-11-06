# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:1343 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 0af5f7c9e03ba94d
require_relative "master/law/universal"

Law.define(:NO_MAGIC) do
  source "Clean Code - no magic numbers"
  ask "Are unexplained numeric literals or booleans carrying domain meaning instead of named concepts?"
  fix "Name the domain meaning and keep the value in one source."
  bad <<~'X'
    sleep 37; if retries > 4; end
  X
  good <<~'X'
    BACKOFF_SECONDS = 37; MAX_RETRIES = 4
  X
end
