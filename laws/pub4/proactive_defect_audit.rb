# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:941 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 5bf30d3bd633aaa2
require_relative "master/law/universal"

Law.define(:PROACTIVE_DEFECT_AUDIT) do
  source "OpenBSD security-audit practice"
  ask "Does an audit stop at recently changed lines or known vulnerabilities when the same defect class can exist elsewhere in the complete high-risk boundary?"
  practice "Audit whole trust boundaries and recurring defect classes, not only the incident that exposed them."
  fix "Trace every entrypoint, caller, state transition and failure path in scope; validate the audit instrument against known positive and negative cases; turn confirmed defect classes into regression tests."
  bad "Patch the reported vulnerability line and stop."
  good "Audit the component and sibling paths for the same defect class, record what actually ran, and add a regression case."
end
