# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:350 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: f16963044acd8756
require_relative "master/law/universal"

Law.define(:WHY_NOT_WHAT) do
  source "Clean Code / Code Complete - comments explain why, not what"
  reads_comments true
  # Two guards, and the second is the one that matters. Anchoring to the start
  # of the comment is not enough, because these words are nouns as often as
  # verbs and a wrapped paragraph puts them at the head of a line: "# set is
  # closed and small" is about the verb SET, "# create is not a failure to
  # lock" is about the create call. All six hits read that way.
  #
  # A comment restating the line below it is terse — that is what makes it
  # worthless, and the fixture is two words. Prose that explains why runs on.
  # Four words is the cut, so `# increment counter` stays caught and a sentence
  # that merely opens with one of these words does not.
  detect do |line|
    body = line[/\A\s*#\s*(.*)/, 1].to_s
    # A restating comment names its object: "increment counter". A function word
    # after the verb means the line is mid-sentence — "get for free" is the tail
    # of "what changed is which one you / get for free", wrapped.
    next false unless body.match?(/\A(increment|set|get|update|return|initialize|create|add)\s+\w+/)
    next false if body.match?(/\A\w+\s+(?:a|an|the|for|of|to|in|on|at|with|from|by|is|are|was|were|it|this|that)\b/)

    body.split.length <= 4
  end
  fix "Comments should explain intent, not restate the code."
  bad "# increment counter"
  good "# retries are capped so a flapping host cannot pin the worker"
end
