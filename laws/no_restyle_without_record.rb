# frozen_string_literal: true

# A restyle is a rewrite of a tuned surface. The corpus answered it only
# with questions an agent grades itself, so "does it look right" answered
# yes all the way to the operator's eye catching the drop. This Law asks
# the review question with the acceptance record as the arbiter: a visible
# change needs a recorded decision owning it - a ux_refinements row, a
# console or prompt byte, an operator directive in PLAN.md - and, where the
# surface renders, a captured render as the evidence. The census grades the
# answer, not the author.
Law.define(:NO_RESTYLE_WITHOUT_RECORD) do
  source "PLAN.md sections 3, 18 and 19; pub4 ux_refinements.yml UX027 and UX028"
  ask "Does this change alter how a surface is seen - boot lines, prompt, face, colours, spacing, copy, " \
      "messages, keybindings - without a recorded operator decision owning it: a ux_refinements row, a " \
      "console or prompt byte in master/data or master/cli, or an operator directive in PLAN.md? And " \
      "where the surface renders, does a captured render (pty capture, screenshot, asciinema) carry the " \
      "evidence, or does the claim rest on reading source? A restyle that lives only in the diff is a " \
      "drop, not a refinement."
end
