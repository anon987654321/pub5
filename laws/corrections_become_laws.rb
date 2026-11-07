# frozen_string_literal: true

# The operator's correction of the dropped boot lived in chat, so it could
# be re-committed against and re-forgotten. pub4 recorded directives as Laws
# (OPERATOR_DIRECTIVE_MEMORY_LANDS_IN_MASTER); this Law makes the recording
# mandatory and immediate, and makes a repeated miss a verdict about the Law
# system rather than the operator.
Law.define(:CORRECTIONS_BECOME_LAWS) do
  source "PLAN.md section 19; pub4 OPERATOR_DIRECTIVE_MEMORY_LANDS_IN_MASTER"
  practice "- **Corrections become law.** An operator correction lands in the same session as a Law " \
           "amendment or a ux_refinements row, not as chat. A second instance of the same miss means the " \
           "Law system failed, not the operator: promote the catching Law - census, fixtures, " \
           "ratification - instead of repeating the apology."
end
