# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/css.rb:371 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 1156ee158d5dad52
require_relative "master/law/css"

Law.define(:NO_DECORATIVE_GRADIENT) do
  source "RENDERED_VALUES and flat design - a gradient wash is a colour the operator did not choose; surfaces are flat tokens"
  detect { |line| DesignMarks.gradient_wash?(line) }
  fix "Paint the surface with its token colour. A fade to transparent over an edge or a scrim under text is allowed."
  bad  ".hero { background: linear-gradient(135deg, var(--a), var(--b)); }"
  good ".hero { background: var(--surface); }"
end
