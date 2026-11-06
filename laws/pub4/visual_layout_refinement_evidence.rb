# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/practice.rb:660 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: b4ef0eb6afc348a9
require_relative "master/law/practice"

Law.define(:VISUAL_LAYOUT_REFINEMENT_EVIDENCE) do
  source "MASTER constitution: rendered-evidence layout refinement"
  practice <<~TEXT
    Refine a rendered layout from measurement, not from reading source alone
    and not from taste. Capture the surface's screenshot before judging;
    compare the captured pair against the owning Laws and find the specific
    violation each proposed edit repairs; cite that Law in the refinement
    record. Repair the shared token contract before page CSS — a page-level
    override that repeats a token value is a finding of its own. Judge only
    with the before/after pair in hand: source inspection alone is not visual
    proof, and a pair whose halves are the same image proves nothing.
  TEXT
  fix "Capture the pair, find the violated Law, repair the token, re-measure the rendered surface."
  bad  "redesigning a layout from source reading, aesthetic opinion, or an after-only screenshot"
  good "captured before/after pair, the violated Law cited per edit, token repair before page CSS"
end
