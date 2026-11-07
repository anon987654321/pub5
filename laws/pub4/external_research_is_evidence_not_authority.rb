# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml EXTERNAL_RESEARCH_IS_EVIDENCE_NOT_AUTHORITY by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 0870c11cb3473620
require_relative "master/lib/master"

Law.define(:EXTERNAL_RESEARCH_IS_EVIDENCE_NOT_AUTHORITY) do
  source "pub4 MASTER/data/laws.yml EXTERNAL_RESEARCH_IS_EVIDENCE_NOT_AUTHORITY"
  practice "Third-party research is evidence bounded by its source, method, population and date; it does not override constitutional Law, operator intent or operator-owned product identity."
  ask "For each external claim, identify its source, author/publisher, publication date, population, method, limitations, and the proposition it supports. Separate measured evidence from opinion and inference. External research may inform decisions but cannot override operator-owned identity, explicit instructions, governing Laws, or observed behaviour. Flag unsupported extrapolation and copied proprietary material."
end
