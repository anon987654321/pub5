# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:219 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 0ddc68effa36a9c0
require_relative "master/law/universal"

Law.define(:NULL_BLINDNESS) do
  source "SQL/Ruby - explicit NULL/nil handling"
  # `= NULL` with no word boundary matched `<= NULL_FLOOR_DB` and
  # `>= NULL_FLOOR_DB` — a float comparison against a dB floor, flagged at
  # error severity, which then gated those files out of the semantic pass
  # entirely. `!= NULL` was also a strict substring of `= NULL`, so that half
  # of the alternation had never done anything.
  # A SET clause assigns, and `SET col = NULL` is how SQL clears a column; the
  # comparison this rule is about starts at WHERE, so the clause between is
  # read out before matching.
  detect do |line|
    (s = line.strip) && !s.start_with?("#") &&
      s.sub(/\bSET\b.*?(?=\bWHERE\b|\z)/i, "").match?(/(?:(?<![<>=!])=|!=)\s*NULL\b|== nil.*column|column.*== nil/)
  end
  fix "Use IS NULL / IS NOT NULL in SQL; .nil? in Ruby."
  bad "UPDATE profiles SET bydel = NULL WHERE deleted_at = NULL"
  good <<~'X'
    WHERE deleted_at IS NULL
    # `= NULL` -> `IS NULL`, in SQL and nowhere else.
    UPDATE profiles SET neighborhood_id = NULL WHERE neighborhood_id IS NOT NULL
  X
end
