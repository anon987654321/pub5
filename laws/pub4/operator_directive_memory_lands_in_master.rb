# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/project_context.yml operator_directive_memory_lands_in_master by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 42309413752c01a3
require_relative "master/lib/master"

Law.define(:OPERATOR_DIRECTIVE_MEMORY_LANDS_IN_MASTER) do
  source "pub4 MASTER/data/project_context.yml operator_directive_memory_lands_in_master"
  practice "Operator directive, 2026-10-03: ALWAYS write memory, rules, logic and harvested findings directly into MASTER - it is the primary surface for external LLMs (Claude, Grok, Codex et al.), so a lesson that exists only in one harness's private memory is invisible to the other sessions and to the runtime. Session memory files remain a per-agent convenience; MASTER is the shared source of truth. Concretely: research harvests, learned constraints and standing directives get an entries: row here (or an edit to the owning data file), with the date in the key."
end
