# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:1854 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: b7ca2a5b46aff681
require_relative "master/law/universal"

Law.define(:RENDERED_VALUES) do
  source "laws.yml RENDERED_VALUES - rendered values and presentation are operator-owned"
  ask "Are colors, typography, sounds, motion, spacing, layout, content, or rendered behavior invented independently of their canonical owner or altered without evidence and approval? For nonvisual artifacts, assess other operator-owned values and contracts; return CLEAN when values remain sourced, truthful and intentional."
  practice "Read canonical values and preserve real-world fidelity; never invent a competing design or configuration authority."
  fix "Use the owning token, configuration, source asset or explicit operator decision and verify the actual rendered result."
  bad "A second color/font/spacing table drifts from the canonical tokens, or a visual claim is made without inspecting the render."
  good "Values flow from their owning source, original media stays truthful, and rendered evidence confirms the outcome."
end
