# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:193 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 22d6afb64e672713
require_relative "master/law/universal"

Law.define(:NO_COLUMN_ALIGN) do
  source "Ruby Style Guide / RuboCop Layout - no token alignment"
  # The character class before `=` is optional. Required, it could only match by
  # backtracking into the run of spaces, so `name    = 1` was caught on three
  # spaces and `result  = x` slipped through on exactly two — the commonest
  # spacing of all. 121 findings under MASTER/lib became 154, and none of the 33
  # is in law/, so the rule was blind to a third of its own subject.
  # A run of spaces inside a quoted string is the string. OPENBSD/dev/perms.sh
  # writes `print "File perms  = $file_perms"`, lining up two labels in the
  # OUTPUT — the one place column alignment is the point rather than the defect.
  detect do |line|
    s = line.strip
    next false if s.start_with?("*") || s.match?(/\A[-=]+\z/)

    line.gsub(/"[^"\n]*"|'[^'\n]*'/) { |m| "\0" * m.length }
        .match?(/\S {2,}(?:=>|[^=!<>]?=[^=>]|:\s)/)
  end
  fix "Remove padding; one space before operators. Column alignment decays and hides diffs."
  bad "name    = 1"
  good "name = 1"
end
