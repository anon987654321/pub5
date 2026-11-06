# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/ruby.rb:48 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 271aecd0d3e815e0
require_relative "master/law/ruby"

Law.define(:GUARD_CLAUSE) do
  source "Ruby Style Guide / RuboCop Style/GuardClause"
  scope :file
  # No /m, and [^\n]* rather than .*: with /m the `.` after `def \w+` matched
  # newlines, so the pattern swallowed the whole file and backtracked — any
  # file containing a def, a later `if`, a later `else` and a trailing `end`
  # matched, and scope :file reports every hit at line 1. It flagged 321 of
  # 2,381 authored Ruby files, each pointing at frozen_string_literal. The
  # lookahead keeps the body inside one method. The original fixture was
  # too permissive to exercise the terminal-branch requirement, so prove! did not
  # catch the detector/fixture mismatch until the detector was tightened.
  # The if and its else must be one block. Allowing any non-def line between
  # them let the match cross an `end` and stitch a method's first `if` — which
  # already returns early — to the `else` of a later, unrelated one. signals.rb
  # was flagged for exactly that: on_int opens with a guard and the pattern
  # reached past its `end` to the next conditional.
  #
  # The backreference pins `else` and `end` to the `if`'s own indent and every
  # line between to a deeper one, so a closed block cannot be crossed. 24 files
  # to 18, and what remains is a method whose whole body is the conditional —
  # which is what the fixtures show and what a guard clause replaces.
  # "A method whose whole body is the conditional" is what the paragraph above
  # claims and what a guard clause can actually replace, but the pattern only
  # anchored the `if` to the first line and never checked the method ended
  # there. display_ok opens with `if streamed` and then prints five footers
  # after the block; returning early from either arm would skip them, so there
  # is no guard clause to flatten it to. The def's own `end` has to follow the
  # conditional's.
  detect do |text|
    match = text.match(/^([ \t]*)def \w+[^\n]*\n\1[ \t]+if [^\n]+\n(?:(?!\1(?:def|end)\b)[^\n]*\n)*?\1[ \t]+else\n(?:(?!\1(?:def|end)\b)[^\n]*\n)*?\1[ \t]+end\n\1end\b/)
    next false unless match

    branches = match[0].split(/^\s+else\s*$/)
    branches.size == 2 &&
      branches.all? { |branch| branch.match?(/\b(?:return|redirect_to|render|head|raise)\b/) }
  end
  fix "Flatten to: return ... unless condition"
  bad <<~X
    def go(x)
      if x
        return run
      else
        return nil
      end
    end
  X
  good <<~X
    def go(x)
      return unless x
      run
    end

    def pick(x)
      if x
        foo
      else
        bar
      end
    end
  X
end
