# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/interface.rb:31 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 4fb91bff35ed08e9
require_relative "master/law/interface"

Law.define(:CLI_TREE_TARGET_RESOLUTION) do
  path "MASTER/lib/cli/"
  source "MASTER CLI - four-tree target addressing"
  ask "When an operator explicitly names MASTER, RAILS, OPENBSD or STUDIO, does the command resolve that target from the repository root through the canonical target resolver rather than assuming the current working directory is MASTER? Return CLEAN when every explicit sibling-tree target follows the shared resolver contract."
  fix "Resolve explicit four-tree targets from Master::REPO_ROOT through TargetResolver; never reinterpret a sibling tree relative to MASTER/lib or the current process directory."
  bad <<~X
    target = File.expand_path("STUDIO/postpro", Dir.pwd)
  X
  good <<~X
    target = resolve_target("STUDIO/postpro")
  X
end
