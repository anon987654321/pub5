# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/project_context.yml operator_agents_token_efficient by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 701cd83cb14553b4
require_relative "master/lib/master"

Law.define(:OPERATOR_AGENTS_TOKEN_EFFICIENT) do
  source "pub4 MASTER/data/project_context.yml operator_agents_token_efficient"
  practice "Report results and blockers only; batch checks into one command; do not\nnarrate routine monitor heartbeats; filter watchers to commits, failures\nand exits; do not re-read what is already in context. Judge another model's\nwork by what its commits change, not by its report: patches from GLM and\nFable on 2026-11-06 ran no tests and most did not hold against the code."
end
