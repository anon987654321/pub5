# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/practice.rb:644 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: fba7d311b1f14db9
require_relative "master/law/practice"

Law.define(:AESTHETIC_DISCIPLINE) do
  source "MASTER constitution: universal visual and typographic principles"
  practice <<~TEXT
    Treat appearance as a consequence of function, proportion, material, use,
    and restraint rather than decoration. Choose typefaces for their function;
    set type to suit its nature; use rhythm, proportion, modulation, and
    harmony. Prefer simplicity, silence, emptiness, useful and unobtrusive
    form, honest materials, durability, and as little intervention as the work
    allows. In code, use meaningful names, small single-purpose functions,
    comments that explain why, and separate error handling from ordinary logic.
    Leave room for pause and imperfection; remove the inessential.
  TEXT
  fix "Choose for function; reduce until only the necessary remains."
  bad  "decorative form, arbitrary typography, or needless visual machinery"
  good "clear hierarchy, proportion, restraint, and visible purpose"
end
