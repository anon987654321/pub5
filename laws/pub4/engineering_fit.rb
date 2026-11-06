# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/practice.rb:677 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: f712c1a3e3f61e6f
require_relative "master/law/practice"

Law.define(:ENGINEERING_FIT) do
  source "MASTER constitution: engineering fit"
  practice <<~TEXT
    Match the solution to the load and its failure modes. Classify the problem
    as under-engineered, over-engineered, or well-fitted and state why. Name the
    users, observed workload and expected envelope, edge cases, lifetimes,
    external dependencies, and blast radius that justify the machinery. For
    capacity or scale claims, distinguish deployed and measured capability
    from a target or design intent; state the workload, environment and evidence,
    or mark the claim INCONCLUSIVE. When materially different shapes remain
    viable, compare their trade-offs (including reuse or no change) and choose
    the smallest correct fit; do not manufacture an alternatives quota. Add
    only what the artifact actually carries; strip machinery the artifact
    never loads.
  TEXT
  fix "State the load and failure modes, then remove everything that does not earn its complexity."
  bad  "a registry and adapter for a single call site with no distinct load"
  good "the smallest coherent solution that covers the observed load"
end
