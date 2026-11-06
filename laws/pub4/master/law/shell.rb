# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/shell.rb (shared code; its Law.define calls moved to laws/pub4/) by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 2c277ae4dcc4d630
require_relative "../lib/master"

# law/shell.rb — every shell law, one Law.define per law.













# DOUBLE_BRACKET lives once, in the registry (js_laws.rb): it reads the
# shebang first — [[ ]] is a keyword in zsh/bash but not POSIX sh, so
# telling a /bin/sh script to use it is telling it to break. A line
# detector cannot see the shebang; the shebang-aware twin wins, the same
# judgment that kept QUOTE_VARIABLES in the registry.

# New. Restores the guard added after the 2026-01-05 incident (16 untracked
# files batch-deleted before a conversion step) that did not survive the
# master.yml -> MASTER migration. Consequence class: unrecoverable data loss.



















































# QUOTE_VARIABLES lives once, in the registry (js_laws.rb): quoting is a
# fact about the interpreter — zsh does not word-split or glob unquoted
# parameter expansions; sh, ksh and bash all do — and only the registry can
# read the shebang. 455 of the deep scan's 573 quoting errors were idiomatic
# zsh flagged by a sh doctrine.

# New (2026-09-17, operator ask). Bash is banned: the deploy target is
# OpenBSD, where bash is not in base and /bin/sh is ksh; the operator's
# dialect is zsh; and a lane's default shell idiom is bash, whose word
# splitting and globbing the QUOTE_VARIABLES comment already had to carve
# around. `sh` shebangs stay legal — vm23's own rc.d and maintenance scripts
# are POSIX sh and must run where bash does not exist — so this law bites the
# one interpreter that is neither portable nor the house dialect.















# New (2026-10-30, operator ask). data/laws.yml `zsh.banned_commands` was a list
# with readers but no Law: MASTER's own shell warned and ran the command, the
# coding-harness hook kept a second copy of the list, and no scan read the repo's
# scripts at all. This is the scan, through the same Io::GnuTextTools lexer the
# hook and Io::Shell judge with, so the three cannot disagree about what a line runs.
#
# zsh scripts only. A #!/bin/sh or ksh script is what ZSH_SHEBANG keeps legal for
# vm23's rc.d and maintenance work, which must run on OpenBSD base, where neither
# zsh nor the replacements this law names are guaranteed.




























































