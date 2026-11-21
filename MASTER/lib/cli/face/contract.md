# Terminal face contract

This contract governs the standalone terminal-face renderer and window components. They share MASTER's runtime state and visual tokens with the web face; they are not a second command router, policy engine, model, voice personality, or source of visual truth.

The default `bin/master` CLI does not mount this face. Its active terminal surface is the Reline prompt, OpenBSD-style dmesg scrollback, and the fixed two-ring mic/TTS indicator in the top-right corner. The full-screen `Face::Window` remains an isolated component, not a CLI entry mode. Tests of that component do not prove that the default CLI paints a face.

## Canonical authority

`MASTER/data/tokens.yml#face_interface` owns shared state names, the stipple profile of each state, interaction/turn/task/tool states, events, prompt tokens, the ASCII ramp and measured ink values, mesh and camera parameters, sampling and fit rules, and declared performance budgets. Change those definitions first; do not copy the values into Ruby constants or browser code. The face contract in the runtime owns the semantic state shape. The terminal renderer implements that contract rather than redefining it.

The optional white swarm is another projection of that same contract. Its geometry,
attractors, force constants, mode multipliers, particle ceiling and glyph ramp live
under face_interface.swarm in tokens.yml and are read by Master::Face::Swarm.
The terminal overlays depth-ranked glyphs onto the current frame from far to near;
MASTER_FACE_SWARM=0 disables this CLI layer. The browser uses the same target field and rank buckets in
face_stipple_system.js. The CLI maps rank through the six-glyph ramp; the web
maps those same rank buckets to neutral brightness because the existing
one-pixel sprite rule keeps physical point size fixed. The size_from_depth token
enables or flattens that rank-based emphasis. Reduced motion freezes positions
and velocities rather than respawning or shrinking the field. The token ceiling
is subordinate to the existing shared point allocation.

## Surface responsibilities

`window.rb` owns the standalone component's terminal lifecycle, input, viewport handling and exit/interruption behavior; the default `bin/master` session does not invoke it. `head.rb` builds the reusable deterministic mesh. `ascii.rb` projects and shades that mesh into terminal cells; the web face ports the same rendering rules using its own surface primitives. Terminal-specific sizing may adapt to the available rows and columns, but shared geometry, glyph choices, rounding and state meaning stay governed by the canonical token document.

Typed input follows `Master::CLI::TurnRouter`, the same command path as `bin/master`. Speech and microphone behavior use the existing voice runtime and explicit user interaction. The face never gains shell, filesystem, network-write or deployment authority merely because it is visible in a browser or full-screen terminal.

## CLI terminal typography

The terminal emulator owns its font family and size. MASTER must not issue
font-changing OSC/escape sequences or pretend that it can set the host's
display size. Prefer the JetBrainsMono Nerd Font Mono build from the official
[upstream release archive](https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.tar.xz),
then any well-rendered fixed-width monospace face. Use a large size: 20–22 pt is a
useful PuTTY starting point; increase it further whenever that improves
comfortable reading. Termux users resize text with pinch zoom.

PuTTY selects the font and point size at *Window → Appearance → Font*.
Termux supports pinch zoom and font selection at *More → Style → Choose
Font*. Termux can also load ~/.termux/font.ttf; run
termux-reload-settings after replacing that file. The operator-facing
setup steps and source links live in MASTER/README.md#terminal-type-and-accessibility.

The CLI prompt and fenced code use the same semantic roles as the browser:
commands, keywords, flags, paths, strings, numbers, comments and outcomes.
ANSI presentation is enabled only when Renderer#terminal_color_enabled?
allows it. Redirected output, NO_COLOR and TERM=dumb remain plain. Nerd
Font private-use glyphs are optional; they never carry meaning by themselves.

The browser transcript uses the 20px terminal-font-size token, 1.5 body leading and a 66ch
reading measure. It preserves line breaks, wraps long output, and does not
shrink code below the surrounding terminal text. Do not align operational
records with padding or fixed-width columns; each event remains one factual
line and the terminal handles wrapping.

Strunk and White govern the words: active verbs, concrete labels, one idea
per sentence, and no needless banners. Bringhurst governs the setting:
hierarchy, a measured line, consistent leading and enough negative space for
the text to breathe. Colour supports meaning; it never replaces it.

## Required behavior

The surface reports actual states, including waiting, interruption, cancellation, warning and failure; it must not imply success from a request being sent or from a flag being set. Meaning must survive when color, motion or audio is absent. Keep operational diagnostics in the OpenBSD-style dmesg stream rather than adding decorative status banners. Outside the face renderer itself, do not introduce ASCII pictures.

Rendering remains deterministic: no random geometry, one canonical ramp, the declared rounding/index rules, bounded viewport work, and the current performance limits. Resizing changes the viewport, not the underlying state or mesh semantics.

## Evidence to accept a change

Review the token-source contract and relevant terminal-face tests, then capture a real terminal frame and a browser frame at representative sizes. Verify state transitions, resize, text entry, microphone permission, speech interruption and visible failure states. Source inspection or a passing unit test alone does not prove that the rendered face is legible or that live interaction works.
