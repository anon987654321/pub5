# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:1827 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 5ac4f848e8ab4bf7
require_relative "master/law/universal"

Law.define(:PROXIMITY) do
  source "laws.yml PROXIMITY - related concepts stay close and cohesive"
  ask "Are related responsibilities, evidence, states, controls or visual elements separated so far that their relationship is hard to understand or keep consistent? Evaluate semantic, structural and visual proximity for this artifact; return CLEAN when the grouping communicates the real relationships."
  practice "Keep pieces together when they change together; separate them when they have distinct ownership."
  fix "Move or group the related elements at the boundary that best reflects their shared responsibility without adding another abstraction layer."
  bad "A control is separated from its state, or related logic is duplicated across unrelated modules."
  good "The structure groups each responsibility and the interface groups information by its actual relationship."
end
