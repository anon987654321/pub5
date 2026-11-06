# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:131 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 7b5bbfcfbef41476
require_relative "master/law/universal"

Law.define(:GUARD_EXPENSIVE_OPS) do
  source "MASTER-native (guard expensive operations); Nielsen heuristic 5, error prevention"
  ask "Does this execute an expensive or destructive operation without confirmation, bounds, or relevant preconditions?"
  # `rm -rf` left for NEVER_BATCH_DELETE, which already owned file deletion and
  # already knew a scoped path from an unbounded one. Both laws claiming it was
  # one question with two instruments, and every one of the twelve hits here was
  # a bounded removal in the deploy pipeline — `doas rm -rf "${app_dir}/public"`
  # — or prose in a runbook. This law is the database sweep.
  #
  # A symbol list names the operations; it does not perform them.
  # `%i[drop_table force_push]` is a list of what needs confirming, and reading
  # it as a drop_table is reading a menu as a meal.
  detect do |line|
    next false if line.match?(/%[iw]\[/)

    line.match?(/\b[A-Z]\w*(?:::\w+)*\.(?:delete_all|destroy_all)\b|\bdrop_table\b|\bTRUNCATE\b|\btruncate_tables?\b/)
  end
  fix "Cost estimate before execution. Require opt-in for danger; scope the delete to a parent."
  bad "Session.delete_all"
  good "user.sessions.delete_all"
end
