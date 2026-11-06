# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/practice.rb:17 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 6a454e8dc8cd2b14
require_relative "master/law/practice"

Law.define(:COLLAPSE_BEFORE_ADDING) do
  source "MASTER constitution (soul.yml absolute.rules)"
  practice <<~TEXT
    before adding machinery, run the universal transformation plan in
    data/laws.yml#transformation_policy. inventory and classify first, then
    follow its declared order and operation descriptions without maintaining
    a second sequence here. recommend rather than mutate when proof is
    insufficient. adding is the last resort and its reason belongs in git
    history. Every kept transformation refreshes the corpus before repair
    resumes.
  TEXT
  fix "before writing a new file, class, or dependency, try nine moves first and in this order."
  bad  "adds a second check script"
  good "extends the check that exists"
end
