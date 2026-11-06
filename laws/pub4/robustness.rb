# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:1818 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: f60846222b5a3f61
require_relative "master/law/universal"

Law.define(:ROBUSTNESS) do
  source "laws.yml ROBUSTNESS - safe failure, security and edge-case handling"
  ask "Across this artifact and its real operating context, what can fail unsafely under invalid input, adversarial use, concurrency, resource pressure, missing dependencies, or partial failure? Name only evidenced failure paths; return CLEAN when the relevant boundary fails safely."
  practice "Treat every boundary and degraded state as a first-class path, not as an exception to the design."
  fix "Close the concrete unsafe path, preserve useful failure context, and prove both the bad and safe paths."
  bad "The happy path succeeds, so malformed input and provider failure are assumed safe."
  good "Input, authorization, resource bounds and failure recovery have explicit evidence-backed behavior."
end
