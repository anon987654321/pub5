# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml ROBUSTNESS_proactive_defect_audit by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 7eb28094df34c94d
require_relative "master/lib/master"

Law.define(:ROBUSTNESS_PROACTIVE_DEFECT_AUDIT) do
  source "pub4 MASTER/data/laws.yml ROBUSTNESS_proactive_defect_audit"
  practice "An audit stops at the reported incident or changed lines without examining the complete high-risk boundary for the same defect class."
end
