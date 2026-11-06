# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/lexical.rb (shared code; its Law.define calls moved to laws/pub4/) by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: e724a9fa2ae58a84
require_relative "../lib/master"

module Master
  module Review
  module Scan
  module Laws
  # Lexical Laws whose detector is a `check` over the whole file; Law.load_all
  # loads them with law/, and the scanner runs every enforceable one.
  # Several are RuboCop-shaped and stay here rather than delegating to RuboCop:
  # each id is a name the law addresses, and delegating renames the law.

  # Defined before the Laws that call it: a Law proves its fixtures as it is defined.
  module SilentRescue
    module_function

    def scan(src, narrow:)
      lines = src.lines
      lines.each_with_index.flat_map do |line, index|
        lineno = index + 1
        next [] if line.match?(/scan:\s*intentional\b/)
        next [] unless matches_mode?(line, narrow:)
        next [] unless discard_body?(lines, index)

        [{ line: lineno, message: "rescue discards error - log, re-raise, or return a meaningful value" }]
      end
    end

    def matches_mode?(line, narrow:)
      stripped = line.strip
      return false unless stripped.start_with?("rescue")

      if narrow
        stripped.match?(/\Arescue\s+(?!StandardError\b|Exception\b)[A-Za-z][\w:]*(?:\s*=>\s*\w+)?\b/)
      else
        return false if stripped.match?(/\Arescue\s+(?!StandardError\b|Exception\b)[A-Za-z][\w:]*(?:\s*=>\s*\w+)?\b/)

        stripped.match?(/\Arescue(?:\s+StandardError(?:\s*=>\s*\w+)?|\s+Exception(?:\s*=>\s*\w+)?)?\b/) ||
          stripped.match?(/\Arescue\s*;/)
      end
    end

    def discard_body?(lines, index)
      line = lines[index]
      if line.include?(";")
        tail = line.split(";", 2)[1].to_s.strip
        return discard_token?(tail) unless tail.empty?
      end

      ((index + 1)...lines.size).each do |i|
        body = lines[i].strip
        next if body.empty?
        return false if handled_body?(body)
        return false unless discard_token?(body)

        # In a predicate, false IS the handling: tts_healthy? rescuing to
        # false has absorbed the error into its answer — the health-check
        # idiom, not a swallow. The fleet's health endpoints carried seven
        # error-severity findings for degrading gracefully. Only nil/false
        # qualify; a predicate rescuing to [] is still discarding.
        return !(body.match?(/\A(?:nil|false)\s*\z/) && predicate_method?(lines, index))
      end
      false
    end

    def predicate_method?(lines, index)
      (index - 1).downto(0) do |i|
        name = lines[i][/^\s*def\s+(?:self\.)?(\w+[?!]?)/, 1]
        return name.end_with?("?") if name
      end
      false
    end

    # Swallow.log is written three ways in this tree: bare, Ground:: and
    # Master::Ground::. All three are a report, so all three are handled.
    def handled_body?(body)
      body.match?(/\A(?:raise\b|warn\b|logger\.|@bus\.publish|(?:Master::)?(?:Ground::)?Swallow\.log)/)
    end

    # `end` on the first non-blank line after a rescue means an empty body:
    # nothing can open between the two. An empty body discards completely.
    #
    # `next` is not in the list, and that is the same argument the predicate
    # exemption above makes. A rescue whose whole body is `next` sits in a loop
    # over members, and skipping the member IS the handling: the method's answer
    # is that this one contributed nothing. All 17 in the four trees are that
    # shape — a census walking files, a check walking hosts — and 16 of them
    # would land at error severity, so adding the token asks the fleet to
    # annotate its own idiom.
    def discard_token?(body)
      body.match?(/\A(?:nil|false|\[\]|\{\}|_\w+|end)\s*\z/)
    end
  end

  


















  # A file that runs itself: `Tool.run(ARGV) if $PROGRAM_NAME == __FILE__`, or
  # the same guard opening a block or closing a `return unless`.
  PROGRAM_GUARD = /^[^#\n]*(?:\$PROGRAM_NAME|\$0|__FILE__)\s*==\s*(?:\$PROGRAM_NAME|\$0|__FILE__)\s*$/
  PROGRAM_PATH = %r{/test/|/db/seeds(?:\.rb\z|/)|\.rake\z|/Rakefile\z}

  




































  













  


















  











  


















  # A skipped test is a passing test to the check ladder. With a reason the
  # skip is a decision someone can revisit; without one it is how an agent
  # turns a red test green. FULL.yml asked for this in three of its rule sets.
  # Minitest takes the reason as skip's argument; a JavaScript .skip or xit
  # has no slot for one, so it takes the comment on the line above.
  




















  # A path to one person's machine works on that machine only. /home/<app>/
  # is the OpenBSD deploy layout and stays legal; a macOS home or a Windows
  # drive in code is someone's checkout leaking in. Tests and comments quote
  # such paths on purpose, as fixtures and as history, and are left alone.
  
















  



























  # A conditional whose branches are the same code decides nothing: either the
  # condition is dead or one branch is a typo. FULL.yml asked for a redundant
  # boolean rule; `x ? true : false` is Ruby's coercion idiom and stays, but its
  # `? false : false` cousin hid in checks/support/page_inventory.rb.
  


























  















  









  # An assignment, then any expression, then a modifier rescue returning a
  # discard. `(?<![=!<>*+\/%|&^-])=(?!=)` keeps comparisons out and lets `||=`,
  # `+=` and friends in, since each is still a binding.
  MODIFIER_RESCUE_DISCARD = %r{(?<![=!<>*+/%|&^-])=(?!=)[^=\n]*\S\s+rescue\s+(?:nil|false|\[\]|\{\})\s*(?:#.*)?$}

  










  # EMPTY_RESCUE was deleted here on 2026-08-12. It shared SilentRescue's
  # discard_body? predicate with the two rules above and differed only in which
  # `rescue` lines it matched, so every finding it produced was already produced
  # by one of them: measured across MASTER at 37 findings, 0 unique. Its own
  # comment claimed it "doesn't re-flag what those already catch"; it re-flagged
  # all 37.
  #
  # It also made severity depend on comma count. Its naked-class branch matched
  # `rescue\s+\S+` — one token — so `rescue Errno::ESRCH` was an ERROR while the
  # identical `rescue Errno::ESRCH, Errno::EPERM` was only NARROW_SILENT_RESCUE's
  # warning. 8 sites carried both severities at once.
  #
  # Coverage is unchanged by construction, not just by measurement, and
  # test_scan_rule_false_positives.rb pins each shape: bare `rescue`,
  # `rescue StandardError` and `rescue Exception` fall to SILENT_RESCUE's
  # non-narrow branch; any other class name, scoped or not, matches
  # NARROW_SILENT_RESCUE.

  

















  




























  

















  

















  































  # `a === b` is JavaScript's identity operator and Ruby's case-equality, and it
  # is exactly three `=` with a space each side — which is what the divider
  # pattern below matches. 486 of this rule's 636 findings across the four trees
  # were `mode === "speaking"` and its like, three quarters of everything it
  # reported. An operand on both sides is what separates the operator from a
  # decoration: a real divider has nothing to its right, or is a longer run, and
  # no dropped line carried a run of four or more.
  IDENTITY_COMPARISON = /[\w)\]}'"]\s*===\s*[\w({\[!'"@$:]/

  





















  # ASCII art is reserved for the face's own renderer. The boot, prompt,
  # source prose and UI chrome remain text; a logo made from punctuation is
  # still a logo even when every character is printable ASCII.
  FACE_ASCII_EXCEPTIONS = %r{(?:^|/)(?:MASTER/lib/cli/face(?:/|\.rb\z)|MASTER/web/public/(?:face_ascii|face_2d_fallback)\.js\z|MASTER/web/test/face_ascii\.test\.mjs\z|MASTER/test/test_cli_ascii_face\.rb\z|MASTER/test/fixtures/face_ascii_frames\.json\z|MASTER/tools/face_ascii_fixtures\.rb\z|MASTER/law/interface\.rb\z)}

  















































  end
  end
  end
end
