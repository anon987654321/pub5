# frozen_string_literal: true

# 875 of the corpus's Laws ride as advisory, and an agent under pressure
# reads advisory as ignorable - that is how the dmesg Law's own subject went
# missing while it sat in the index. The admission contract says advisory is
# the entry state, not a lesser state: the Law governs the files it reaches
# now, and enforcement arrives when the census and the operator's
# ratification do. The duty in between is reconciliation.
Law.define(:ADVISORY_MUST_BE_RECONCILED) do
  source "PLAN.md sections 5 and 19; registry/laws.yml admission contract"
  practice "- **Advisory is not ignorable.** A Law in advisory lifecycle still governs the files it " \
           "reaches: before a task lands, run the gate over the touched scope and answer every finding - " \
           "fix it, or record an exemption with an expiry. An advisory finding left unanswered in touched " \
           "scope is an unmet acceptance row, not a preference."
end
