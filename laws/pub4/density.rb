# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:1845 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 1617a53f486c02d7
require_relative "master/law/universal"

Law.define(:DENSITY) do
  source "laws.yml DENSITY - signal over noise and no needless information"
  ask "Does any part of this artifact consume attention without adding relevant meaning, evidence, action or necessary context? Look across code, prose, UI, status output and visual ornament; return CLEAN when every element earns its place."
  practice "Prefer the shortest complete expression, not the shortest expression that omits a necessary fact."
  fix "Remove repetition and ornament, then restore any evidence or context needed to make the result complete."
  bad "Repeated labels, redundant prose, decoration or duplicated logic competes with the actual task."
  good "Each statement, control, visual emphasis and abstraction contributes distinct useful meaning."
end
