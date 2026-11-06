# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:1761 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 7a5354ef311c53aa
require_relative "master/law/universal"

Law.define(:VERIFICATION_REQUIRED_FOR_COMPLETION) do
  source "MASTER constitutional completion policy"
  ask "Does this claim of completion have direct evidence from the actual resulting artifact or executed check, rather than intention, absence of an error, or an unrun test?"
  practice "Completion is an observed state, not a promise."
  fix "Run the relevant proof and report the observed result; otherwise report the work as unresolved."
  bad "Done because the patch was written."
  good "Done after the changed code, relevant tests and final state were actually inspected."
end
