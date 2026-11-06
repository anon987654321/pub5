# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/interface.rb:65 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 1e1d2c2c6d7cd738
require_relative "master/law/interface"

Law.define(:OPENBSD_DMESG_CONSOLE_STYLE) do
  path "MASTER/lib/voice/"
  source "OpenBSD dmesg - xsa/openbsd-dmesgs and Master::Trace::Dmesg"
  ask "For startup, status, progress and operational events, does CLI output follow the native console idiom: append-only, one factual event per line, a stable subsystem0: or unit0 at parent: prefix, truthful status, and useful scrollback? Look for banners, decorative panels, ASCII art outside the face, badge-like status, repeated progress chatter, and information hidden behind color alone. Conversational replies may retain plain Markdown when structure serves the content. Return CLEAN when operational output remains clear in a pipe, serial terminal and saved transcript."
  fix "Use Master::Trace::Dmesg's existing unit0: grammar for operational events; emit one concise factual line per event, order events by occurrence, keep state and recovery explicit, and preserve plain-text meaning without relying on ANSI or animation. Conversational replies may use restrained, width-aware Markdown. Do not create a second event logging format."
  bad <<~'X'
    ╭─ MASTER ───────────────────────────╮
    │  ◉ ONLINE  MODEL: ready  TOKENS 5k │
    ╰───────────────────────────────────╯
  X
  good <<~'X'
    model0: ready
    context0: 5k/128k
    fix0 at scan0: 3 files changed
  X
end
