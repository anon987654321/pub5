# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/project_context.yml operator_fix_mobile_first_and_simplify by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: d467374769b02850
require_relative "master/lib/master"

Law.define(:OPERATOR_FIX_MOBILE_FIRST_AND_SIMPLIFY) do
  source "pub4 MASTER/data/project_context.yml operator_fix_mobile_first_and_simplify"
  practice "When /fix takes screenshots it captures and judges 390, 360 and 320 wide\nfirst; desktop widths come only after every mobile capture of the pass, and\na capped pass drops desktop captures first. /fix has a simplify stage\nmodelled on Claude Code's /simplify (reuse, simplification, efficiency,\naltitude): it only removes or merges, a count must fall (selectors,\ndistinct values per property, DOM depth, variants, SCSS lines), and the\npixel diff plus the computed-value audit must show no visible change or a\nchange toward the Laws; each count becomes a ratchet. Visual work is held\nto measured values, state matrices, boundary widths, per-component specs,\nan independent reviewer and a guard for every fixed defect."
end
