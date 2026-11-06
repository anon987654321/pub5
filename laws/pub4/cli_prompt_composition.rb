# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/interface.rb:44 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 5e41c40b22c61236
require_relative "master/law/interface"

Law.define(:CLI_PROMPT_COMPOSITION) do
  path "MASTER/lib/voice/renderer/"
  source "OpenBSD dmesg console discipline; shell line editing remains the input transport"
  ask "Does the interactive prompt remain a restrained OpenBSD-console line that shows the checkout/tree, current directory, active conversation destination, Git state, meaningful phase/error state and input token, with no Starship/powerline-style segments or decorative emphasis? Is it bounded, single-line, plain in scrollback and cheap to redraw? Return CLEAN when it follows the dmesg-first house style."
  fix "Keep one compact text line with checkout/tree-relative path, active destination, plain Git state, phase and shell token. Prefer ASCII and stable spacing; avoid badges, icon glyphs, color-coded segments, boxes and duplicated status. Cache or bound Git probes and move detail to /status, /doctor or /help."
  # Quoted heredocs: the examples quote instance and local variables, and an
  # interpolating heredoc evaluates them against the Builder at load time —
  # one #{e.class} here once made every law definition crash the registry.
  bad <<~'X'
    def prompt
      system("git status")
      "◉ #{@path} [model=#{@model} tokens=#{@tokens} memory=#{@memory}]"
    end
  X
  good <<~X
    def prompt
      [path, branch, phase, token].compact.join(" ") + " "
    end
  X
end
