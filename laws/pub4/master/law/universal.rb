# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb (shared code; its Law.define calls moved to laws/pub4/) by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: e34daeccf7b65906
require_relative "../lib/master"

# law/universal.rb — every universal law, one Law.define per law.
# DEAD_CODE lives once, in the scanner registry (MASTER/law/ruby.rb): it anchors the
# terminator to the line start, walks indentation to tell a dedent (block
# over, next line reachable) from a continuation, and knows else/elsif/when/
# rescue/ensure open new reachability. This file regex called `x = return_val`
# a terminator and every method's last line unreachable.

# Reviewed 2026-10 against MDN Baseline, WCAG 2.2 mobile guidance and web.dev
# Core Web Vitals thresholds. Feature status changes; consult the current
# Baseline record during review rather than treating this snapshot as evergreen.












































































































































# LAW_OF_DEMETER lives once, in the registry (universal_rules.rb), which
# folds MESSAGE_CHAIN: it excludes numeric dot-chains (1.2.3.4 is an IP,
# not a message chain), stdlib transformation chains (.to_s.strip.empty? is
# idiomatic), and re-tests after blanking strings and parens. This bare
# regex flagged every version number and gem constraint in the tree.

























































# NO_FLAG_ARGUMENTS lives once, in the registry (universal_rules.rb): only
# a positional boolean default is a flag argument; a keyword default
# (stream: false) is fine API design, and this bare regex flagged every one.










































































# TYPOGRAPHIC_EXCELLENCE lives once, in the registry (universal_rules.rb):
# it knows shell arg separators and Open3 calls are not prose; this bare
# twin flagged doc-comment placeholders and double-counted every hit.

# TYPOGRAPHY_DISCIPLINE lives once, in the registry (universal_rules.rb): it
# skips comment-leading lines and yaml frontmatter and wants a 4+ run, where
# this per-line twin flagged every section comment, diff header and
# frontmatter delimiter in the tree.














































































# Constitutional migration batch 2: architecture, design, and verification laws.
# Semantic laws live here once their executable question, remedy, and worked
# examples are defined. The YAML catalogue remains temporarily for compatibility;
# SemanticLaw#from_law gives these definitions precedence during the migration.
































































































































































































































































# Constitutional migration batch 3: kernel and foundational principles.

































































































# Constitutional migration batch 4: architecture and security principles.








































































































































































































































































# Constitutional migration batch 5: foundational architecture, clarity, and runtime behavior.





























































































































































































































































# Constitutional migration batch 6a: SOLID and abstraction laws.





























































# Constitutional migration batch 6b: design, functional, and refactoring laws.





































































































































# Constitutional migration batch 7a: user experience laws.





































































































# Constitutional migration batch 7b: interface, LLM, and reliability laws.





















































































# Constitutional migration batch 7c: public surface, refactoring, and prose laws.













































































































# Rule-system laws. These govern the instrument itself, so they are universal
# practice/semantic laws rather than language-specific regexes.
































































# The remaining constitutional principles have explicit semantic evaluators.
# Their detector adapters are modality-specific, while each Law applies to every
# artifact surface through the canonical assessment matrix.













































module Master
  module Review
    module Scan
      module Laws

      # SQL strings embedded in Ruby DB adapter files are expected — only flag
      # actual mixed-medium template files.
        # Retired registry twins — each lives once, in law/:
        #   MEANINGFUL_NAMES, WHY_NOT_WHAT
        # (test_scan_rule_contracts proves each reaches findings through the bridge).

        # NO_MULTIPLE_LANGUAGES lives once, in law/css.rb — fixtures attached, any narrowing
        # this version had learned ported there (2026-08-21 twin retirement).

        # SAFE_NAVIGATION lives once, in law/ruby.rb — fixtures attached, any narrowing
        # this version had learned ported there (2026-08-21 twin retirement).

        



















        














      # Only positional boolean defaults are flag arguments. Keyword defaults
      # (stream: false, enabled: true) are not — they're fine API design.
        




















      # A chain reaches a stranger when it navigates: order.buyer.profile.address
      # asks four objects in turn. A step that transforms what the last one
      # returned is not a new friend, so `files.uniq.sort.reject` and
      # `text.each_line.with_index.map` talk to one object throughout. Data and
      # prose have no calls at all: in YAML and Markdown the old line match read
      # hostnames and file names (pubmed.ncbi.nlm.nih.gov, three.face.module.js)
      # as chains, and its `.any?` exclusion never matched, because `\b` after
      # `?` needs a word character to follow. A chain is read from its head
      # only; one rooted in a constant (Rails.application.config.x) starts at
      # a global the caller already knows, and is not matched halfway along.
        DEMETER_TRANSFORMS = %w[
          map select reject filter filter_map flat_map each each_with_index each_with_object with_index
          each_line each_char lines chars bytes split uniq sort sort_by min_by max_by group_by partition
          tally sum count flatten compact reverse first last take drop zip keys values to_a to_h to_s
          to_i to_f to_sym join strip chomp downcase upcase include? any? all? none? empty? size length
          find detect slice match? freeze dup tap then gsub sub tr squeeze delete delete_prefix delete_suffix
          casecmp round abs zero? positive? negative? push merge fetch dig value!
          forEach filter reduce some every trim toString padStart padEnd toFixed toLowerCase toUpperCase
          replace startsWith endsWith
        ].to_set.freeze

        DEMETER_CHAIN = /(?<![\w.@$])(?:@{1,2}|\$)?\b[a-z_]\w*[?!]?(?:\(\))?(?:\.[a-z_]\w*[?!]?(?:\(\))?){3,}/
        # Platform globals every caller already knows, as a constant receiver is.
        DEMETER_GLOBALS = %w[document window globalThis].freeze

        DEMETER_NOISE = [
          %r{\w+://\S+},
          /%[wi]\[[^\]]*\]/,
          /["'`][^"'`]*["'`]/,
          /\b[\w-]+(?:\.[\w-]+)*\.(?:rb|js|mjs|ts|css|scss|erb|html|yml|yaml|json|md|txt|png|svg|jpg)\b/,
          /\d+(?:\.\d+){2,}/,
        ].freeze

        

























      # Generic names: only short or clearly placeholder names. `data` and
      # `result` are contextually meaningful in most Ruby code.

        # Copy a visitor reads carries the ellipsis, and an aside a spaced en
        # dash (operator, 2026-11-06), so a literal "..." or "--" in copy is
        # ASCII standing in for them. The dash and quotes in running copy are
        # PARENTHETICAL_DASH's and QUOTES_BY_LOCALE's (law/typesetting.rb).
        # Terminal output stays ASCII (Law::TERMINAL_OUTPUT_PATH, and a line
        # that prints: puts, warn, a logger), so the CLI, the REPL prompt and
        # dmesg lines are out of this Law's reach.
        TERMINAL_PRINT =
          /\b(?:puts|warn|print|printf|logger|abort|\$stderr|\$stdout|console\.(?:log|warn|error))\b/.freeze

        






















      # Box-drawing glyphs, and only those. A run of dashes or equals signs is
      # NO_ASCII_LINE_ART's question, and reading it here reported one divider
      # under two ids while also calling a Markdown table's delimiter row
      # decoration, when that row is the syntax that makes the table.
        BOX_DRAWING = /[─-╿]/

        









      # The front page is where a document speaks first, and 2.1.6's tracking
      # is a repair for capitals, not a licence to open with them: a letterspaced
      # caps headline shouts, and letterspacing the lowercase instead is 2.1.7's
      # named offence. So the headline a reader meets first - a title page, a
      # cover, a landing, a document H1 - is set in the text face, mixed case
      # or true small caps. One bare token is a name (OPENBSD, LICENSE), not a
      # headline. Section heads stay ALL_CAPS_NO_TRACKING's question. Non-cased
      # scripts hold no \p{Lu} and so never fire.
        FRONT_PAGE_HEADLINE = /\A\s{0,3}(?:#\s+(.+?)\s*#*\s*\z|\\(?:title|chapter)\s*\{([^}]*)\}|<h1\b[^>]*>([^<]*)<\/h1>\s*\z)/i
        FRONT_PAGE_MARKUP = /\\[A-Za-z]+|[*_`\[\]]|&[A-Za-z]+;/

        

























      # NULL_BLINDNESS lives once, in law/ (domain files) — the second
      # retired twin (see the old backlog). This block's regex matched IS NULL, the
      # correct form its own message prescribed, and needed a path exemption
      # to stop reporting the fixer that emits that string as a repair. The
      # law version detects `= NULL`, proves itself on fixtures the inverted
      # detector would have failed, and needs no exemption.

      # SECRET_PROXIMITY lives once, in law/ — the third retired twin. The two
      # regexes were byte-identical; the registry block was a pure duplicate.

# MAGIC_COLOR lives once, in js_laws.rb (applies_to css/scss/html/js — where colors
# live). A second copy here with no applies_to double-counted every css/scss color
# under the same id (a SINGULARITY violation) and added no coverage worth keeping.

      # UNBOUNDED_RETRY lives once, in law/ (domain files) — the first of the
      # 72 law/registry twins retired (see the old backlog). The narrowing this block
      # learned — keyword not symbol, not predicate, not identifier, not regex
      # alternation, not a line continuation — moved into the law's detector
      # with each shape pinned as a good fixture, which is what the registry
      # version never had. Its law/ self-exemption dies with it:
      # canonical law/ sources arrive conducted, and rule sources that
      # spell the pattern in strings are counted and triaged rather than excused by path.

        




















      # Bias: SIMULATION. soul.yml's anti_simulation forbids will, would, could
      # and might beside its demand for evidence — a diff for a change, output
      # for a completion — so the words are forbidden where the program reports
      # on work: a promise in any file ("I will", "let's"), and a future or
      # conditional inside a message it prints. A conditional anywhere else
      # names a hypothetical. "This test would pass having measured nothing"
      # and "what evidence would falsify your criticism" are both correct, and
      # every finding sampled over MASTER before this narrowing was that shape.
        SIMULATION_PROMISE = /\b(?:I|we)\s+(?:will|would)\s+\w+|\blet(?:'s|\s+us)\s+\w+/i
        SIMULATION_REPORT = /
          \b(?:puts|print|warn|say|status|info|notice)\b.*["'][^"']*
          \b(?:will|would|could|might)\s+(?!not\b|have\b)\w+
        /x

        
















      # Bias: COMPLETION_THEATER — ellipsis/etc as placeholder outputs.
      #
      # A placeholder "etc" is lowercase, bare, and not part of a path. Being loose
      # about that (/\betc\.?\b/i) matched `require "etc"`, `Etc.nprocessors` and
      # every /etc/… deploy path — 12 of selfcheck's 71 findings, none real. See
      # the old backlog, Scanner noise.
      #
      # `|`, `:` and `[` join the path characters because a word that sits inside
      # a regex alternation is a token in a pattern, not prose. Two lines in the
      # tree were reported for years on that shape and both are lists of real
      # names: ast_fixer's `%r{/OPENBSD/(?:etc|usr|var)/}` — the OPENBSD mirror
      # guard, at error severity, so `rake selfcheck` was red on the rule that
      # protects /etc — and a stdlib allowlist naming `etc` among a dozen others.
      # Measured over all four trees: exactly those two go, 57 findings stay.
      # `(` and `)` are deliberately NOT in the sets: "(etc.)" in prose is the
      # placeholder this rule exists to find.
        # `-` joins them for the same reason: `"etc-pre-sync"` is a label naming
        # the directory, and no abbreviation is ever hyphenated onward.
        PLACEHOLDER_ETC = %r{(?<![\w/|:\[-])etc\.?(?![\w/|\]-])}

        STDLIB_ETC_REQUIRE = /\brequire\s+["']etc["']/

        # /etc is a directory, and the exclusions above only knew it when a
        # slash was adjacent. Every other way this tree spells that path counted
        # as theater: File.join(ROOT, "etc", "rc.d"), `OPENBSD/{etc,usr,var}`,
        # the %w list of directory names in tools/doc_paths.rb — 25 of this
        # rule's 40 findings on 2026-09-06, none of them a placeholder.
        # `require "etc"` is the same lesson, learned once for one line.
        PATH_ETC = /["']etc["']|\{[\w,]*\betc\b[\w,]*\}|\betc(?=\s+(?:usr|var)\b)/

        # A comment is a comment wherever it starts, and in whatever language.
        # The rule skipped a line that opens with `#` and read the same words as
        # theater when they followed code, so `|| continue   # skip CAM, TS,
        # screener, etc.` was a finding and the same sentence on its own line was
        # not. Ruby's `#{` and a shell `$#` are not comment openers.
        #
        # `//` and `/* … */` for the same reason, found when MASTER/web joined
        # the corpus: a CSS comment reading "(mood changes etc)" and a JS one
        # listing "style bleed, mood arc, vertical timbre, etc." were the only
        # two findings in 164 files, and both were prose.
        #
        # Per language, because a comment opener in one is data in another. The
        # first version applied all three everywhere and `CONFIG_GLOBS =
        # ["etc/crontab*", "etc/*.local", …]` in OPENBSD lost everything from
        # its `/*` onward — leaving `"etc` at the end of the line, which then
        # read as the abbreviation. The ratchet caught it at 0 -> 1.
        HASH_COMMENT = /(?<![$\\])\#(?!\{).*\z/

        SLASH_COMMENT = %r{//.*\z|/\*.*?(?:\*/|\z)}
        SLASH_COMMENT_EXTENSIONS = %w[.js .mjs .ts .jsx .tsx .css .scss].freeze

        


































        # Interpolation is not injection when the adapter did the quoting. A
        # bind parameter cannot be an identifier, so
        # `conn.execute("DELETE FROM #{conn.quote_table_name(table)}")` is the
        # documented way to name a table — and flagging it tells the reader the
        # rule does not know the fix it demands. Only an interpolation that is
        # nothing but one quoting call is spared; a second term inside the
        # braces still fires.
        QUOTED_INTERPOLATION = /
          \A[\w.:@]*\b
          (?:quote_table_name|quote_column_name|sanitize_sql_array|sanitize_sql|quote)
          \([^()]*\)\z
        /x
        INTERPOLATION = /\#\{([^{}]*)\}/

        



































        # NO_COLUMN_ALIGN lives once, in law/universal.rb — fixtures attached, any narrowing
        # this version had learned ported there (2026-08-21 twin retirement).

        # STRICT_MODE_ZSH lives once, in law/shell.rb — fixtures attached, any narrowing
        # this version had learned ported there (2026-08-21 twin retirement).

        


















        # pledge(2) and unveil(2) restrict a process once, at boot, in a fixed
        # order: promise the syscalls, deny the filesystem root, open the paths
        # back, then lock. Ground::Pledge holds that order in stage1_boot! and
        # stage2_lock!, and a caller that assembles its own
        # promise string somewhere else restricts a different process than the one
        # data/laws.yml#law_map pledge_unveil describes.
        #
        # Two shapes, and the second is why the wrapper is not simply exempt:
        # unveiling "/" with anything but the empty permission leaves the whole
        # filesystem reachable, and that line lives inside lib/ground/pledge.rb.
        # The choke-point half is what the wrapper is allowed to break.
        #
        # A bare `pledge(` is deliberately unmatched. pledge(2) in prose and the
        # Fiddle extern both read that way, so the namespace is what separates a
        # call from a mention — and an `include Pledge` caller writing bare
        # `pledge("stdio")` is outside this rule's reach.
        























        # The audit log is the only record of which tools ran, and it is worth
        # exactly as much as its oldest surviving line. Trace::Log::Audit
        # subscribes to tool:before and appends; opening that file for writing, or
        # File.write-ing it without mode "a", discards every earlier entry and
        # leaves a log that reads full and remembers one turn.
        #
        # Scoped to the sinks: a file that subscribes to tool:before is an audit
        # sink, and this asks how it writes. It does not ask whether every action
        # publishes tool:before — a subscription that never happens leaves no line
        # to read — so a tool that mutates without publishing is outside its reach
        # and stays the gap data/laws.yml#law_map audit_logging records.
        



















      end
    end
  end
end
