# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml APPLICATION_IS_UNIFORM by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 2abd71dd0cbc99cd
require_relative "master/lib/master"

Law.define(:APPLICATION_IS_UNIFORM) do
  source "pub4 MASTER/data/laws.yml APPLICATION_IS_UNIFORM"
  practice "Every file passes through every law in both modalities. There is no path that skips a law. There is no file exempt by location. A file's kind is a fact, recorded; a finding is made against the fact, not against a bypass."
  ask "Given the complete inventory of in-scope files and the registered deterministic and semantic Laws, decide whether every file is classified once, every applicable deterministic Law is executed, every semantic Law is reviewable, and no file is silently exempt because of its directory or extension. Require inventory rows and run receipts, not a claimed total. Pass only with zero unexplained skips; fail with exact file/Law pairs; abstain if coverage evidence is absent."
end
