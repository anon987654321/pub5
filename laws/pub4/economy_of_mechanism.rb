# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:976 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: b0d3ab7afcb53e28
require_relative "master/law/universal"

Law.define(:ECONOMY_OF_MECHANISM) do
  source "Saltzer & Schroeder - economy of mechanism; OpenBSD integrated-base discipline"
  ask "Is the trusted computing base too large, indirect, dependency-heavy or split across competing owners to inspect and verify as one small mechanism?"
  practice "Prefer a small, coherent, auditable base with one owner for each policy and mechanism. Integration reduces version skew and hidden interfaces; it does not justify merging unrelated product identities or trust domains."
  fix "Shrink and isolate the trusted path; reuse the platform's established base mechanisms; give each decision one owner; keep privilege transitions explicit; and remove machinery that does not improve measured correctness, security or operability."
  bad <<~'X'
    def authorize; 1200 lines of mixed parsing, IO and policy; end
  X
  good <<~'X'
    def authorize(request); policy.allow?(request); end
  X
end
