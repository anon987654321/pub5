# frozen_string_literal: true

# MASTER interface laws: terminal, transport and capability-facing presentation.
# Keep these together so interface defects become executable law without growing
# universal.rb into another monolith.

Law.define(:NO_TRANSPORT_WRAPPER_IN_SOURCE) do
  source "MASTER source integrity - presentation wrappers do not belong in source files"
  scope :file
  detect do |text|
    text.match?(/\A\s*<(?:sub|sup|pre|code)>/i) ||
      text.match?(/\n\s*<\/(?:sub|sup|pre|code)>\s*\z/i)
  end
  fix "Remove presentation/transport wrapper markup from the source file and preserve its Ruby contents verbatim."
  bad <<~'X'
    <sub>
    # frozen_string_literal: true
    require "fileutils"
    end
    </sub>
  X
  good <<~'X'
    # frozen_string_literal: true

    require "fileutils"

    def run = true
  X
end

Law.define(:CLI_TREE_TARGET_RESOLUTION) do
  path "MASTER/lib/cli/"
  source "MASTER CLI - four-tree target addressing"
  ask "When an operator explicitly names MASTER, RAILS, OPENBSD or STUDIO, does the command resolve that target from the repository root through the canonical target resolver rather than assuming the current working directory is MASTER? Return CLEAN when every explicit sibling-tree target follows the shared resolver contract."
  fix "Resolve explicit four-tree targets from Master::REPO_ROOT through TargetResolver; never reinterpret a sibling tree relative to MASTER/lib or the current process directory."
  bad <<~X
    target = File.expand_path("STUDIO/postpro", Dir.pwd)
  X
  good <<~X
    target = resolve_target("STUDIO/postpro")
  X
end

Law.define(:CLI_PROMPT_COMPOSITION) do
  path %r{/MASTER/(?:lib/cli/|lib/voice/renderer/)}
  source "OpenBSD dmesg console discipline; shell line editing remains the input transport"
  ask "Across the CLI and REPL prompt renderer, does the input line remain one restrained, bounded OpenBSD-console prompt? Show only useful checkout/tree path, current directory, destination, meaningful Git state, phase when it changes, and the input token. Keep the cursor and editable input stable while asynchronous events arrive. Reject Starship/powerline segments, decorative emphasis, repeated model/token counters, hidden probes on every redraw, and duplicated status. Details belong in existing /status, /doctor and /help commands. Return CLEAN when the prompt is plain in scrollback and cheap to redraw."
  fix "Keep one compact ASCII prompt with checkout-relative path, useful Git state and input token. Preserve the editable line and never let asynchronous status overwrite it. Avoid badges, icon glyphs, color-coded segments, boxes, repeated counters and expensive redraw probes. Move detail to existing status commands; do not add prompt frameworks or new configuration."
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

Law.define(:OPENBSD_DMESG_CONSOLE_STYLE) do
  path %r{/MASTER/(?:lib/(?:cli|trace|voice)/|bin/)}
  source "OpenBSD dmesg - xsa/openbsd-dmesgs and Master::Trace::Dmesg"
  ask "Across the pub5 MASTER CLI and REPL - boot, prompt, help, routing, progress, status, errors, voice and media feedback - does the operator surface follow OpenBSD console discipline? Operational events are append-only: one factual event per line, stable subsystem0: or unit0 at parent: grammar, observed state, and useful scrollback. Distinguish configured from observed health: the presence of a URL, token, executable or saved preference alone does not establish reachability or readiness. Distinguish an available provider from the provider selected for a specific request. The implementation favors a small auditable surface, conservative defaults, least privilege, bounded work, explicit recovery and fail-closed action gates. Reject banners, decorative panels, ASCII art outside the face, badge-only status, repeated progress chatter, state hidden behind ANSI, optimistic readiness, or success inferred from process creation. Conversational replies may retain plain, width-aware Markdown. Return CLEAN only when the terminal remains useful in a pipe, serial terminal and saved transcript."
  fix "Use Master::Trace::Dmesg's existing unit0: grammar for operational events; emit one concise factual line per event, order events by occurrence, and keep state and recovery explicit. Report configured, discovered, reachable, selected and successful as distinct evidence states; claim ready only after the relevant bounded check or operation succeeds. Prefer the smallest auditable implementation, conservative defaults and existing permission gates. Preserve plain-text meaning without relying on ANSI, color or animation. Keep details behind existing /status, /doctor and /help surfaces. Do not add another event, status or logging framework."
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

Law.define(:VOICE_FAILURES_ARE_ACTIONABLE) do
  path %r{/MASTER/lib/(?:cli|io|voice)/}
  source "OpenBSD-style explicit failure reporting - degraded capability is state, not noise"
  ask "When voice or media synthesis, stream transport, player startup, playback, or their CLI/REPL dispatch fails, does the runtime emit one bounded actionable state and preserve the observed reason? Distinguish a rendered artifact, a started process, and audible output; distinguish a normal exit from signal termination; and use only declared, bounded fallback paths. Do not retry or print the same failure without a state change. Return CLEAN when the operator can tell what happened, what remains available, and the next safe action."
  fix "Return a typed failure/result, retain the measured cause for /status or /doctor, and emit one concise Dmesg line. Report exit status or terminating signal explicitly. Prove that an output artifact exists before passing it to a player; never infer audible success from a PID. Rate-limit repeated diagnostics and use only declared fallback paths."
  bad <<~'X'
    rescue StandardError
      warn e
      nil
    end
  X
  good <<~'X'
    rescue StandardError => e
      @last_error = "#{e.class}: #{e.message}"
      warn_once("voice0: unavailable - #{@last_error}")
      fallback_or_false
    end
  X
end

Law.define(:CLI_ANALYZE_TARGET_ROUTING) do
  path "MASTER/data/patterns.yml"
  source "MASTER CLI - deterministic repository analysis targets"
  scope :file
  ask "Does natural-language analysis of an explicit repository path enter the deterministic operator route instead of falling through to the model and guessing about file existence?"
  fix "Register analyze/analyse/inspect with a path capture and map it to the canonical review route."
  bad <<~'X'
    commands:
      review:
        patterns:
        - "\\b(?:review)\\s+(.+)"
  X
  good <<~'X'
    infer:
      commands:
        analyze:
          patterns:
          - "\\b(?:analyze|analyse|inspect)\\s+([\\w./-]+)"
          capture: path
  X
  detect do |text|
    section = text[/^    analyze:\s*\n(.*?)(?=^    [a-z][a-z0-9_-]*:\s*$|\z)/m, 1].to_s
    section.empty? || !section.match?(/analyze|analyse|inspect/) || !section.match?(/capture:\s*path/)
  end
end

Law.define(:CLI_FACE_DEDICATED_TTY) do
  path "MASTER/lib/cli/command_registry.rb"
  source "Terminal discipline - full-screen face must not share line-editor input"
  scope :file
  ask "Does the /face command obtain an independent terminal stream instead of sharing Reline/session stdin with the full-screen face?"
  fix "Open /dev/tty and pass that handle as both the face input and output; close it after the face exits."
  bad <<~'X'
    Face::Window.new(turn:, event_bus: container[:bus]).run
  X
  good <<~'X'
    terminal = File.open("/dev/tty", "r+")
    Face::Window.new(turn:, event_bus: container[:bus], input: terminal, output: terminal).run
  X
  detect do |text|
    text.include?("Face::Window.new") &&
      !text.match?(/File\.open\(["']\/dev\/tty["'],\s*["']r\+["']\)/)
  end
end

Law.define(:CAPABILITY_STATUS_MUST_BE_TRUTHFUL) do
  source "OpenBSD-style status reporting - unavailable capabilities are not ready"
  ask "Does a status, progress, success, pending, sent or delivered label, or a service readiness report, " \
      "claim a state the system has not observed: from a flag, an optimistic default, or before the " \
      "server or capability answered? State must derive from observed outcome and keep the failure reason."
  fix "Derive service state from the capability's actual health or retained error; report degraded or unavailable with the reason instead of ready."
  bad <<~'X'
    when "voice" then ENV["MASTER_TTS_DEGRADED"] == "1" ? "degraded" : "ready"
  X
  good <<~'X'
    when "voice"
      reason = Voice::Speech.last_error || Voice::Playback.last_error
      reason ? "degraded: #{reason}" : "ready"
  X
  detect do |text|
    text.match?(/when\s+["']voice["'][^\n]*ENV\[/) &&
      text.match?(/["']ready["']/)
  end
end

Law.define(:SIGNATURE_MOMENT) do
  path "RAILS/"
  source "Interaction design - distinctive, frequent, functional moments"
  ask "Does this product surface have one deliberately distinctive interaction that users encounter often, improves the task rather than merely decorating it, matches the product's character, and remains effortless and accessible? Return CLEAN when an existing interaction already serves this role."
  fix "Choose one existing high-frequency interaction and give it immediate, restrained, distinctive feedback. Do not invent a feature solely for delight, duplicate the pattern elsewhere, or make motion or haptics the only signal."
  bad "Add a decorative animation with no relationship to the user's action."
  good "Make one frequent action produce immediate visual state, optional tactile feedback, and a clear success or failure result."
end

Law.define(:DIRECT_MANIPULATION_FEEDBACK) do
  path "RAILS/"
  source "Direct manipulation - immediate perceptual feedback"
  ask "When a user directly presses, drags, swipes, or dismisses something, does the interface acknowledge that input immediately rather than waiting for a delayed release or network result? Check pointer, keyboard, touch, visual state, and failure recovery together."
  fix "Respond at input start with a small state change, keep the gesture tied to the pointer while it moves, and retain a non-motion keyboard equivalent. Do not make the early feedback imply success before the action is actually committed."
  bad "click -> request -> finally show any indication that the press happened"
  good "pointerdown/active -> immediate press state; commit -> explicit success or failure state"
end

Law.define(:WAITING_STATE_MEANING) do
  path "RAILS/"
  source "Interaction status - useful feedback during dead time"
  ask "When a user is waiting for a meaningful result, does the surface identify what is happening or what is being prepared, rather than exposing only a generic spinner or unexplained motion? Keep the message brief, truthful, localised, and independent of animation."
  fix "Expose a short status label alongside the existing progress or skeleton state. Keep it accurate and persistent long enough to orient the user; never invent progress or use animation as the only meaning."
  bad "<div class=\"spinner\" aria-label=\"Loading\"></div>"
  good "<div aria-busy=\"true\"><span>Loading results...</span><div class=\"skeleton\" aria-hidden=\"true\"></div></div>"
end

