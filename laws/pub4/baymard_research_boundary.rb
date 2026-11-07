# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml BAYMARD_RESEARCH_BOUNDARY by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 2dea5aa43150daa7
require_relative "master/lib/master"

Law.define(:BAYMARD_RESEARCH_BOUNDARY) do
  source "pub4 MASTER/data/laws.yml BAYMARD_RESEARCH_BOUNDARY"
  practice "Public usability research, including Baymard's ecommerce research, informs independently worded and context-specific assessments. It is evidence, not constitutional authority: it does not override operator-owned product identity, the needs of the actual audience, or observed behaviour. It never implies affiliation or certification and does not reproduce proprietary guideline text, screenshots or benchmark material."
  ask "For every use of external usability research, check source identity, date, geography, participant population, methodology, sample size, task context, limitations, and exact claim supported. Reject claims of affiliation/certification and reproduction of proprietary text or screenshots. Test whether recommendations reflect the actual audience and observed product behaviour rather than copying a generic guideline. Separate evidence from normative authority. Return concrete source-to-claim mappings and counterexamples."
end
