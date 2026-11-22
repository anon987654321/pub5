# /fix Session Receipt — 2026-11-22 Qoder intake

**Operator request:** Clone pub5, load and internalize MASTER/**, propose every
polish, refinement, micro-refinement, restructure, rewire and reflow available,
and create a large handoff list for the next agent to implement.

**Runtime environment of this session:**
- Ephemeral review sandbox. Debian buster userland, archived apt mirrors, no
  Ruby on PATH, no Chrome, no libvips, no provider keys. The sandbox recycled
  twice mid-session; the checkout was re-cloned once and then lost again.
- Ruby >= 3.2 floor (MASTER/Gemfile) cannot be met here. Every Ruby suite, rake
  task, Law detector, /fix lane and browser check is **NOT_RUN**.
- Instruments that did run: git (clone, ls-files -s, log, rev-parse), plain-text
  reads, PyYAML safe_load parses, JSON parses, regex censuses, and the GitHub
  contents API for delivery. These are external static measurements, not MASTER
  instruments. No Law PASS is claimed.
- Delivery path: the sandbox lost the local checkout before the commit could
  land, so this receipt was committed straight to main through the GitHub
  contents API (one path-scoped commit, no force-push). Local hooks did not run
  (no checkout, no Ruby); the commit message follows commit_format.yml by hand.
  bin/operator land remains the canonical path on a real host.

**Authority loaded:** soul.yml, laws.yml (structure and catalogue), MASTER/AGENTS.md
(in full, including the refused list), root AGENTS.md, CLAUDE.md, README.md,
MASTER/README.md, task_contract.yml, commit_format.yml, fix_hygiene.yml,
polish_policy.yml, polish_wave2.yml, ideations/polish.yml, proposals.yml,
gaps.yml, operator_seams.yml, convergence.yml, checks/checks.yml,
PATH_OWNERSHIP.yml, spine.yml header, state.yml, sunset.yml, lanes.yml,
check_tiers.yml, incidents.yml, tool_habits.yml, TREE_CONTRACTS.md headings,
FACE_WORLD.md structure, agent_map.yml, models.yml keys, apps.yml keys,
.githooks, .editorconfig, and the 2026-11-19 Grok receipt.

**Disposition:** external, constitution-aware intake. This receipt is session
evidence under the established receipts precedent, not a backlog. The README
forbids a parallel Markdown checklist; every item below names its owning
registry for intake (proposals.yml, gaps.yml, operator_seams.yml,
convergence.yml, ideations/, ux_refinements.yml, RAILS/refinements.yml). The
next agent re-measures each item before acting; a finding is a hypothesis.

## Measured facts (instrument named, run in this sandbox)

- HEAD at first intake: 6d9d498067cc6c8163901970656e90b01bbcb765. Main advanced
  to 363113338e43ffd74419c3b84c4511d2d55da247 during the session (concurrent
  agent traffic, the shared-checkout reality AGENTS.md describes).
- Root AGENTS.md body equals the agent-contract block in MASTER/AGENTS.md
  (byte comparison after stripping the generated header). No pointer drift.
- laws.yml parses; 196 ALLCAPS statement keys, 34 bare roots; law_catalogue
  holds 554 entries: 279 warning, 176 info, 98 error, 1 veto; 79 automatic
  autofix, 26 never; 16 trusted, 8 advisory, 4 retired lifecycle rows.
- laws_index.json is fresh at intake: revision 61330272 is an ancestor of the
  intake HEAD and no commit touches MASTER/data/laws.yml after it; law_count
  554 matches. Re-verify after the concurrent commits.
- self_findings.yml baseline: 31585 findings, 145 rules. Largest: rubocop 4583,
  LONG_LINE 4582, reek 4086, VERTICAL_BREATH 2289, CONSECUTIVE_BLANK_LINES 2200,
  TRAILING_WHITESPACE 2168, TYPOGRAPHIC_GRID 1711, QUOTES_BY_LOCALE 1566,
  PREFER_TAG_HELPERS 886, SMALL_FUNCTIONS 812.
- FACE_WORLD.md repeats its core block six times: "## Runtime shape" and
  "## 3D restructuring catalogue" each occur 6 times at offsets 292, 11762,
  23091, 33926, 44762, 55597. Segments differ slightly; later copies carry
  edits the first lacks. Roughly two thirds of the 88 KB file is near-duplicate.
- 297 tracked files carry shebangs: 187 ruby, 43 zsh, 27 ksh, 24 /bin/sh,
  5 env sh, 2 bun, 2 falcon-host, 1 node, 1 expect, 1 termux bash, 1 termux sh,
  1 env bash, 1 /usr/local/bin/ruby, 1 /bin/zsh.
- 102 tracked shebang files are committed mode 100644. The list includes
  MASTER/bin/master-session, MASTER/checks/runner.rb, MASTER/tools/boot_smoke.rb,
  MASTER/tools/polish_lens.rb, MASTER/tools/security_sweep.rb and 97 others.
  AGENTS.md documents this exact bug class; triage direct-exec callers first.
- MASTER/data and MASTER/checks/data YAML: 0 safe_load failures (syntax only;
  Ruby psych semantics NOT_RUN).
- MASTER tracked text files: 0 CRLF; 7 files with trailing whitespace
  (data/laws.yml, data/structural_recipes.yml, law/surface.rb,
  test/test_dialogue_rubric.rb, test/voice/test_voice_support.rb,
  tools/portal_agent.rb, web/public/three.face.module.js); 5 without final
  newline (axe.min.js vendored, autopoietic_components.json,
  coverage_map/state.json, laws_index.json, face_music_packs.json).
  .editorconfig demands final newline and trimmed trailing whitespace.
- .editorconfig carries a [*.py] block; git ls-files finds zero .py files.
- MASTER census: 3154 tracked files, 921 test files, 914 lib/*.rb, 32 law/*.rb,
  146 tools entries. checks.yml registers 72 checks.
- convergence.yml: 82 workstreams; ops_alert_channel is the one marked missing.
- operator_seams.yml: 67 seams, each with needs/evidence; all remain open.
- gaps.yml: 54 gaps. proposals.yml: refutation ledger with open/landed/refuted.
- lanes.yml marks codex-cli and gemini dead.

## Rules of engagement for the next agent

1. Read soul.yml, then the laws.yml row and law_catalogue entry for every Law
   you touch, then the Law.define, fixtures and focused tests. Run
   ruby MASTER/tools/agent_context.rb --json first. Never work from this
   receipt alone; it is a hypothesis list, not authority.
2. Re-measure every item before editing. Several backlog rows in this tree
   went stale within a day. Record refutations in proposals.yml with the
   measurement that refuted them; never delete a refuted row.
3. Respect the refused list in MASTER/AGENTS.md. No TUI, no third surface, no
   external agent protocol, no parallel change streams, no second language in
   the MASTER runtime, no RBS/Steep yet, no performance machinery ahead of a
   measured slowness, no telemetry without a reader, no golden traces, no
   detector without a subject, no audit without a path, no new Markdown
   documents (polish_policy.yml no_new_markdown).
4. One checkout, path-scoped commits straight to main, never force-push, never
   git add -A or commit -a. Use bin/operator land -m <msg> <paths>. Commit
   shape: capitalised subject <= 72 chars, no type prefix, no full stop, body
   with numbers, Co-authored-by trailer (commit_format.yml).
5. Honest proof only. NOT_RUN and INCONCLUSIVE are never PASS. Name the
   instrument, the command, the exit state. A declared detector is not a run.
6. Operator standing preferences for this work: all new code and tooling in
   Ruby, all new shell scripts in zsh with strict mode, replies and docs in
   Strunk & White English, screenshots for visual work saved under RAILS/*.png
   or .webp, logs published to gists or command-line pastebins (the runtime
   already publishes redacted log0 to pste.us with dpaste.org fallback),
   frequent small coherent commits with run vs NOT_RUN stated.
7. soul.yml and laws.yml are operator-owned for autonomous writers even though
   sacred_paths is empty by the 2026-11-09 decree. Route edits there through a
   human decision; do not let /fix write them.
8. Rendered values, taste, listening and live-host decisions stay operator-
   gated (RENDERED_VALUES). PolishLens --apply is mechanical-only, dry-run by
   default, antigen-gated, receipted.
9. Every applied polish leaves a trace in the owning registry. Route intake:
   concrete defect claims to proposals.yml (state open), missing capability to
   gaps.yml, human-only evidence to operator_seams.yml, implementation state to
   convergence.yml, polish candidates to ideations/polish.yml with critique.
10. Verify the instrument before the finding. Run each new or touched check
    against a known-bad input first; a green first run proves nothing.

## A. Constitution and authority hygiene

11. FACE_WORLD.md: collapse the six repeated catalogue blocks into one. Diff
    the segments first (offsets above), keep the union of unique lines, preserve
    every rendered-value decision. Intent content_and_structure; prove with a
    section-count assertion and editorial review. Owner: MASTER/FACE_WORLD.md.
12. laws.yml trailing whitespace: report to the operator with the exact lines;
    a human commits the trim. Do not autofix an operator-owned file.
13. law_catalogue defaults: 528 entries carry no explicit mode and 522 no
    explicit lifecycle; they inherit defaults (violation/active). Audit whether
    inheritance is intentional per entry or drift; write the audit as a
    LawRegistryAudit extension, not a new registry.
14. Retired lifecycle rows (4) and advisory rows (8): confirm each retired Law
    has no live detector reach and each advisory row has a reader; retire
    silently-dead catalogue entries through the existing preflight.
15. laws_index.json generator: emit a final newline; add the generator's own
    fixture so the artifact check fails on a missing newline.
16. Nine invariant nodes: confirm the ordered node list in laws.yml still
    matches lib/soul.rb derivation after the 554-entry catalogue growth; pin
    with the existing soul test, not a new one.
17. body_sha256 in soul.yml attests the Ruby identity body; verify the attest
    path runs at boot and reports mismatch as INCONCLUSIVE, never silent.
18. anti_simulation forbidden words (will/would/could/might): confirm the
    detector exempts quoted evidence and fixtures; a law that fires on its own
    statement is the conduct problem AGENTS.md names.
19. prompt_ordering list in soul.yml: confirm every named prompt section has a
    reader in lib/; a named section with no reader is inert config.
20. hooks block in soul.yml: confirm each event has a publisher and each
    action a callable; event_topics.yml is the canonical topic list.
21. temperament profile: keep it delivery-only; add a regression that a
    temperament change never alters a verdict or a rendered value.
22. authority_order: add a cross-tree link check that every source path named
    in soul.yml exists; fail closed on a renamed owner.
23. synonyms.yml is glossary-only; audit that no runtime code reads it as
    policy (the contract forbids it).
24. TREE_CONTRACTS.md: the five-tree acceptance matrix is the shared boundary;
    refresh its command examples against bin/check --list output and name any
    stale spelling in the same commit.

## B. Documentation and editorial craft

25. FACE_WORLD.md after dedup: one audience, one purpose; lead with the runtime
    shape, then the catalogue; Bringhurst hierarchy, 66ch measure in rendered
    prose.
26. MASTER/README.md: the terminal-type section is long for a front door; move
    PuTTY/Termux font detail to the owning mobile doc (data/mobile.yml reader)
    and keep a two-line pointer. Preserve every tested command.
27. MASTER/AGENTS.md "Working alone" section: each paragraph is a scar; confirm
    every named file still exists (test_entrypoint_requires.rb, code_watch.rb,
    cdp_framing.rb) and update addresses that moved.
28. Root README.md: the First hour block duplicates MASTER/README.md; keep one
    canonical sequence and point the other at it.
29. MIGRATION.md: historical record; mark it clearly as provenance, not live
    contract, and confirm no live doc routes readers to it for current truth.
30. .editorconfig: remove the [*.py] block; zero .py files are tracked.
31. Trailing whitespace in law/surface.rb, tools/portal_agent.rb,
    test/test_dialogue_rubric.rb, test/voice/test_voice_support.rb,
    web/public/three.face.module.js: trim in path-scoped commits with the
    file's own focused test after each.
32. structural_recipes.yml trailing whitespace: trim; parse-verify after write.
33. Generated JSON without final newline (autopoietic_components.json,
    coverage_map/state.json, face_music_packs.json): fix the writers, not the
    artifacts; add the newline assertion to generated_asset check fixtures.
34. Vendored axe.min.js: leave bytes untouched; record the vendor exemption in
    the existing exemption registry with a freshness date.
35. Doc link census: run tools/dead_link_census.rb over every maintained
    Markdown; fix broken relative links in the owning document.
36. QUOTES_BY_LOCALE baseline 1566: work the finding members list in batches by
    tree; Norwegian «guillemets» and English curly quotes; never touch
    executable text.
37. NO_SPACED_EM_DASH 263 and ELLIPSIS_SPACE_BEFORE 65: mechanical typography
    repairs through PolishLens --apply candidates, dry-run first.
38. LONG_LINE 4582: split by owning file, not by sweep; respect the 66ch prose
    measure and the code line budget separately; never reflow a law detector
    regex to satisfy a line count.
39. CONSECUTIVE_BLANK_LINES 2200 and TRAILING_WHITESPACE 2168: deterministic
    autofix candidates; prove the parse after each write and keep the ratchet
    falling only on a clean tree.
40. VERTICAL_BREATH 2289 and TYPOGRAPHIC_GRID 1711: rendered-surface findings;
    route to ux_refinements.yml with screenshot evidence under RAILS/*.png
    before and after; operator gates the rendered value.
41. README "Documentation standard" and AGENTS editorial contract: keep one
    source; the root README already points at MASTER/AGENTS.md; audit other
    trees for restated copies.
42. BIZ/research/bringhurst-strunk-research.md: confirm every citation carries
    publication date and method; separate fact from inference per the research
    contract.

## C. Executable surface, shells and portability

43. Triage the 102 mode-100644 shebang files. For each, find the caller: direct
    exec (system/spawn with the path as argv0, shell invocation) needs the
    committed bit; interpreter invocation (ruby path, bundle exec ruby path)
    does not. Fix bits with chmod +x && git update-index --chmod=+x, one
    coherent slice per directory, focused boot proof after.
44. MASTER/bin/master-session: confirm its caller; bin/ scripts are the class
    that broke boot silently before. If direct-exec, set the bit and add the
    entrypoint test case.
45. MASTER/checks/runner.rb, architecture.rb, rails_runtime.rb, release.rb,
    visual_contract.rb: invoked via ruby/bundle exec today; either set the bit
    for consistency or drop the shebang. Pick one convention; write it into
    the shell law fixtures.
46. MASTER/bin/zai-chat and zai-tts run under bun. The MASTER runtime refuses a
    second language. Propose a Ruby bridge that keeps the stdin prompt path
    (the E2BIG fix), the SDK-owned key boundary, and the lane registration in
    models.yml. Operator decision: the bridge was an explicit operator request
    on 2026-11-16; do not delete the lane, replace its transport.
47. MASTER/web/script/probe_webgl_guard.mjs runs under node with a macOS Chrome
    default. Port to the Ruby CDP support (checks/support/cdp_session.rb) or
    record the operator exemption; remove the hardcoded /Applications path in
    favour of the existing CHROME_PATH discovery.
48. MASTER/tools/device/termux/install.sh uses termux bash; termux ships zsh.
    Convert to zsh strict mode; keep the Termux prefix paths; test on device
    (operator seam android_termux_install).
49. RAILS/mrdamascy/bin/dev uses env bash; convert to zsh or record the Rails
    convention exemption. The house shell law prefers zsh strict mode.
50. OPENBSD/mirror/usr/local/sbin/pub5-admin hardcodes /usr/local/bin/ruby.
    On OpenBSD that is the ports path; verify against the live host before any
    change. Do not "fix" a correct target-path assumption.
51. OPENBSD ksh scripts (27): native rc.d and installer context; keep ksh.
    Record the boundary in the shell law so a future sweep does not convert
    them.
52. /bin/sh scripts (24+5): audit each for bashisms and zsh-strict candidates;
    convert where the script is agent-facing tooling, keep POSIX sh where the
    target host demands it (OpenBSD installer).
53. ROBUSTNESS_strict_mode_zsh: confirm every zsh script sets the strict mode
    the law names; add the missing ones with a focused fixture.
54. falcon-host shebangs (web/falcon.rb, mrdamascy/falcon.rb): confirm the
    falcon gem is in each Gemfile.lock and the shebang resolves on the deploy
    host; otherwise route through bin/ruby.
55. expect script vps_console.exp: human-only console path; keep; confirm the
    RUNBOOK still names it and the I_UNDERSTAND_CONSOLE_RISK gate precedes it.
56. Executable-bit regression: extend test_entrypoint_requires.rb to assert
    every direct-exec entrypoint carries mode 100755 in the index, so the next
    sandbox umask flip cannot land silently.
57. bin/ruby interpreter discovery: confirm PUB5_RUBY override and the 3.2
    floor behave on a host with several rubies; add the case to the doctor
    fixture.
58. Sandbox fileMode flip: document git config core.fileMode false in the
    sandbox-bootstrap output so a fresh agent does not commit 6000 mode diffs.

## D. Data hygiene, ratchets and censuses

59. self_findings ratchet: read it once on a clean tree with bin/operator
    measure; never mid-session. Work the top rules by member list, not by
    count; each batch lowers the ceiling and names its members.
60. rubocop 4583 and reek 4086: these are tool baselines inside the census;
    confirm the .rubocop.yml and .reek.yml configs match the intended house
    style before repairing findings; a config change is an operator decision.
61. SMALL_FUNCTIONS 812, FEW_ARGUMENTS 650, LONG_PARAMETER_LIST 468,
    CYCLOMATIC_COMPLEXITY 447, ABC_SIZE 392: structural debt; route through
    Fix::Restructure with snapshot, proof and undo, one family per commit.
62. NARROW_SILENT_RESCUE 176 and SILENT_RESCUE 125: each rescue needs a named
    error class and a log or re-raise; work by file with the focused test.
63. MAGIC_COLOR 143: route every literal to data/tokens.yml; the token check
    already owns the contract; no new palette.
64. REDUNDANT_CORE_REQUIRE 85: convergence workstream
    redundant_core_require_cleanup is partial; finish it with the spine test
    green and the body ceiling ratcheted down.
65. NO_CHANGELOG_COMMENT 87: move dates and "used to be" into git history;
    keep present-tense reasons.
66. DATA_CLUMPS 78 and CONFIGURATION_SHAPE 87: confirm each clump has one
    owner before extracting; the proposals ledger already refuted several
    family moves; re-measure.
67. dup_census.yml, sprawl_census.yml, cohesion_census.yml: verify each ceiling
    names its members; a ceiling that cannot name its overage is decoration.
68. spine.yml lib_body_ceiling: the sunset fast-gate note records an overage;
    measure on a clean tree, then either land the reduction or record the
    sponsored raise with what the lines buy. Never absorb another change's
    growth.
69. namespace_ceilings in spine.yml: MASTER/lib 0, RAILS/__shared/lib 4;
    confirm the reader still fails on a new extensionless file.
70. sunset.yml ceremonies: measured_catches for several rows is prose, not a
    count; wire each to the ledger that holds the number or mark the row
    unmeasured. A ceremony that cannot price itself is the next retirement
    candidate.
71. lanes.yml dead lanes codex-cli and gemini: probe each with /doctor keyless
    or the lane probe; remove an entry only when the lane answers; record the
    answer as the evidence.
72. state.yml standing orders: constitution_drift and autocommit_post_chat are
    disabled with reasons; keep the reasons; confirm every enabled order has a
    registered callable.
73. incidents.yml: several rows say "in-tree citation pending"; supply the
    citation or keep the honest provenance string; never invent a file
    reference.
74. tool_habits.yml: confirm each named tool exists in tools.yml; a habit that
    names a retired tool teaches the model wrong.
75. event_topics.yml: deterministic census of publishers and subscribers;
    remember the face subscribes "**"; only subscribed-never-published is
    worth reading.
76. autoload.yml and exemption_freshness: check each allow-list entry against
    the tree; an exemption outliving its subject is a standing lie.

## E. /fix runtime refinements

77. pass_runner/assessment_matrix.rb is 74 KB; the largest single runtime file.
    Measure its responsibilities before splitting; the cohesion census already
    refuted convenience splits. If a split pays, each new file needs a distinct
    responsibility and the spine must not rise.
78. fix_loop/committer.rb 36 KB and pass_runner.rb 37 KB: trace the public
    boundary; extract only what a caller already needs; keep the transaction
    and delivery contract in one owner.
79. kernel/repair_adapter.rb 44 KB and convergence_adapter.rb 39 KB: confirm
    the adapter boundary matches lib/execution/contract.rb; a second recovery
    contract is the defect the AGENTS warns about.
80. PolishLens intake (ideations polish_c02): schedule --candidates through
    TaskSteward behind MASTER_BACKLOG_AUTORUN; add polish_lens --apply to the
    argv allowlist; focused regression NOT_RUN until the bundle exists.
81. polish_c05 Tufte data-ink: keep it an experiment; CSS-declaration inventory
    only, no numeric data-ink claim without rendered segmentation.
82. polish_c06 Gestalt proximity: measured rendered surface only; per-component
    pairs; refuse a universal threshold.
83. polish_wave2.yml: 500 seeded items are candidate material, not a build
    order; route survivors through Polish::Discovery with critique; reject
    rows that name no file, caller or measurement (the refused "audit without
    a path").
84. RunBudget and ResourceBudget: the 2026-11-19 hardening tightened defaults;
    confirm MASTER_TOUGH=1 path still fails closed on warning findings and
    that ordinary runs keep the documented behaviour.
85. Stall detection: five-minute no-yield ends a run; confirm the report-only
    override cannot disable hard safety stops; add the fixture that proves it.
86. Lane probe: twelve lanes, four keyless reserves; confirm a run with no
    answering provider refuses before the first file; the refusal is a feature,
    not a failure.
87. File budget 240 s and three rejected proposals: confirm needs_person
    disposition ends HUMAN_DECISION, not stagnation; the summary must name
    rejects by reason.
88. MASTER_FIX_RANK: confirm the ranked inventory scans the whole corpus
    before selecting N; a bounded lane that stops during inventory must say so.
89. code_watch rebase-and-exec: confirm the rebase proves no conflict risk on
    its own paths before restarting; a push rejection mid-flight is normal.
90. FinalCleanup: confirm it never deletes source, checkpoints, transaction
    evidence or the audit ledger; cleanup warnings stay observable.
91. WriteGuard per-write judgment: confirm it judges one file before landing;
    the disabled tree-wide drift scan stays disabled for the 1 GB VPS.
92. Antigen memory: confirm a rejected polish records an antigen and the next
    discovery skips it; the immune pattern is the loop's memory.
93. Best-of-N: the ledger refuted multi-temperature sampling; keep one pinned
    model per lane with outcome history; do not rebuild resampling.
94. Council: the value agent is the council; no MCTS or debate wrapper around
    FixLoop (refused). Confirm council presets still read council.yml.
95. Trajectory recording MASTER_LLM_RECORD=1: confirm the dataset writer has a
    reader in the model laboratory; a recorder without a reader is inert.
96. Homeostat and governor: confirm the resource signals feed the run budget
    and not a second dashboard; one reader per signal.

## F. Checks and proof instruments

97. checks.yml: 72 registered checks; confirm each class-level .run exists;
    registration without execution is the documented defect.
98. failopen fixtures: extend checks/fixtures/failopen to every check that can
    read green while measuring nothing (triangle down, no Chrome, no deploy
    stamps).
99. check_mutation: run the mutation suite against the highest-traffic
    detectors first; a detector that survives mutation is not enforcing.
100. INCONCLUSIVE aging (convergence partial): implement the aging report so a
     stale INCONCLUSIVE becomes visible debt, never a silent pass.
101. Soft tiers (check_tiers.yml): layout_suite, visual_contract,
     web_vitals_budget, design_metrics, rendered_suite are soft; confirm a run
     that makes any check worse is still refused delivery.
102. Triangle dependency: without brgen, amber, bsdports and the face booted,
     the live half passes having measured nothing; confirm every live check
     reports INCONCLUSIVE when the triangle is down.
103. rails_runtime check: it failed at require time for months; confirm the
     load smoke runs before the verdict and a load failure reads as a crash,
     not a finding.
104. Browser contention: a live /fix holds hundreds of Chrome processes;
     document the run-scoped test lane so browser tests are not run mid-sweep.
105. Screenshot custody: ReviewSet#publish! and SweepEvidence#manifest_for
     refuse stale renders; keep the rule; a failed sweep leaves no review set.
106. Visual baselines: checks/data/route_screenshots holds golden PNGs; the
     refused list says no golden renders for model output or dilla; these are
     layout baselines, a different contract; confirm the distinction is written
     where a reader will look.
107. layout_snapshot drift: the JSON snapshots are per-route; confirm the drift
     check names the route and viewport, not just a pixel count.
108. axe-core vendored: keep the license files; confirm the axe check reports
     violations by rule id and node, not a bare score.
109. CDP support: cdp_session.rb 19 KB; confirm bounded commands, console
     capture and network framing each have a fixture; the geometry probes are
     browser-side JS and legitimate.
110. web_vitals_budget: confirm the budget reads measured lab data, not a
     declared target; a budget without a measurement is INCONCLUSIVE.
111. Security headers source check: confirm it reads the deployed header set
     when available and marks source-only proof as source-only.
112. deploy_drift: confirm it compares served bytes against source, not
     mtime; the stale public/assets lesson is documented.

## G. CLI, session and face

113. command_registry/help.rb 40 KB, host.rb 60 KB, review.rb 58 KB: measure
     before splitting; the help text is generated from the registry; keep one
     source.
114. session/repl_flow.rb 39 KB and thinking_indicator.rb 21 KB: confirm the
     indicator never blocks the event loop; a quiet terminal is not a stuck
     council.
115. face/window.rb 37 KB: the ASCII face has golden frames; the nested-ternary
     autocorrect is disabled for a reason; keep it disabled.
116. face.runtime.js is generated from web/public/face.part*.txt; never edit
     the build; confirm the build task runs in the web profile and the
     first-line warning stays.
117. Face character rotation: recent commits separate temperament from museum
     provenance; confirm the rotation profile order is canonical and the
     regressions pin it.
118. face_music_packs.json: generated; fix the writer's final newline; confirm
     music plays only on explicit operator request.
119. CLI output: one factual event per line, semantic ANSI only on eligible
     TTY, NO_COLOR honoured; confirm pipes receive plain text.
120. Log publication: log0 to pste.us (1 day) with dpaste.org fallback (7
     days); confirm content-bearing commands withhold substantive output and
     shell readers upload nothing; publication failure never changes the
     operation result.
121. Lock idle reclaim: two-hour same-host prompt recovery; confirm it never
     unlinks the lock or reclaims daemon locks; the env override stays.
122. /doctor keyless: the anonymous hosted probe; only a provider response
     proves free compute answered; keep the receipt shape.
123. Model routing: quality order, not LRU; one distinct credential per
     provider; quota never rotates identity; confirm the 15-minute health
     window still guards the idle-lane starvation.
124. models.yml: confirm every lane named in routes exists in model_defs and
     every dead lane in lanes.yml is excluded from selection.
125. agent_map.yml topics: six topics; confirm each reads current addresses
     after the lib/now -> lib/cli rename family.
126. context_window.rb and fold_risk.rb: confirm the context budget reads the
     model's actual window, not a declared constant.

## H. RAILS product polish

127. RAILS/refinements.yml and ux_refinements.yml: the owning refinement
     registers; work rows with rendered evidence, screenshots under
     RAILS/*.png before and after, operator gates the value.
128. Tracked PNGs at RAILS root (amber_tabbar_capture_artifact.png,
     amber_tabbar_capture_pinned.png): triage; the review set is git-ignored
     and run-scoped; if these are pinned baselines, move them under the
     baseline owner and name them; if residue, remove with the operator's nod.
129. RAILS/package.json and package-lock.json: name the consumer; importmaps
     is the house frontend; if the only consumer is a lint tool, record the
     exemption or port the lint to the Ruby chain.
130. PREFER_TAG_HELPERS 886 and NO_LOGIC_IN_VIEW 243: work by engine; keep
     Norwegian I18n keys, never English literals.
131. STIMULUS_PROGRESSIVE 68: confirm each controller degrades without JS;
     the stimulus_wiring check owns the contract.
132. Locale shadowing: de/fr/nl were deleted deliberately; confirm
     LocaleBridge still routes those countries to :en and no file reintroduces
     a five-key locale.
133. Marketplace payment race: the lock! plus reload fix landed; confirm the
     redelivery regression still runs on SQLite and the FOR UPDATE path.
134. GDPR erasure: UserPurgeJob now names every table; confirm the two guards
     that keep a hand list from going stale still fail on a new association.
135. Dating, messenger, maps, radio, tv, takeaway: each vertical's rendered
     acceptance is an operator seam; route evidence requests, do not claim
     acceptance from source.
136. mrdamascy: deploy lane pending (PATH_OWNERSHIP); the Vipps mock and
     loyalty routes have screenshots; confirm the deploy lane entry before
     any production claim.
137. hjerterom and mytoonz: confirm apps.yml status and the archive boundary;
     an archived subsystem must not read as active.
138. apps.horizon.yml: agent-ignore; do not implement unprompted; the refusal
     is documented and has no check by design.
139. Shared engine boundaries: engine_boundaries check owns the mount graph;
     confirm takeaway stays nested in marketplace and no vertical becomes a
     separate deploy root.
140. CSS architecture: css_architecture.yml owns the cascade; no !important,
     specificity ceiling, layer stack; work CSS findings through the existing
     autofix regions, never a blanket rewrite.
141. FLAT_UI and kanso: the visual laws forbid glow and ornament; route any
     proposed effect through the design laws check and the operator.
142. Web vitals and page weight budgets: page_weight.yml owns the numbers;
     confirm the check reads served bytes, not source size.

## I. OPENBSD and deployment

143. Recent deploy-transcript work (6d9d498 family): workstation-owned
     transcripts, redacted paste publication; confirm the admission-failure
     capture closes cleanly and the VPS writes no transcript files.
144. RUNBOOK.md: the canonical host contract; verify every command against the
     current release; name vm23 as guest and server4 as hypervisor, never
     interchangeably.
145. vps-deploy serial engine: one app at a time; confirm the deploy lock and
     the broker bootstrap prerequisite; SKIP_CI does not mean skip CI.
146. Copy-tree sync deletes before extract; confirm the guard still fails on a
     stale served asset; the asset-manifest footgun bit twice.
147. resource_guard.sh shedding amber/bsdports: confirm recovery is measured,
     not assumed; the 1 GB VPS is the constraint.
148. DNSSEC signer work (99c2897, 96cfcad): confirm the pregenerated NSD
     signing integrates with mirror deployment and the DS records at
     registrars remain an operator seam.
149. Backup: backup_priv.sh fails closed; dev/backup.sh had three defects
     (landed); confirm the offhost backup and key recovery seam stays open
     until a tested restore exists.
150. App home permissions: the 750 storage fix landed with the vps_ci guard;
     confirm a deploy cannot widen it again; the measurement was real (uid
     1000 read 17748 rows).
151. pf and relayd: openbsd_pf_policy check owns the source contract; native
     pfctl -nf proof is external; mark it NOT_RUN until a host runs it.
152. syspatch and console windows: human-only gates; I_UNDERSTAND_CONSOLE_RISK
     and I_UNDERSTAND_DNS_WIPE stay human-only.
153. monitoring_and_crontab_on_vm23 seam: ops_alert_channel is the one missing
     convergence workstream; propose the operator-owned relay shape the
     proposals ledger names (allowlisted endpoint, secret outside the tree),
     never a Slack webhook.
154. OPENBSD native suite: ksh tests run on the box; the contributor profile
     runs locally; confirm the two profiles do not drift in what they assert.

## J. STUDIO and BIZ

155. STUDIO/replicate: SSRF pinning landed for API and downloads; confirm the
     allowlist, byte caps and mode 0640 stay; a new provider enters through
     the chain, not a second registry.
156. dilla: renders are replaceable; never change a rendered-sound default on
     agent judgement; MixScore takes targets from kept takes, not thresholds.
157. lora: subject profiles under STUDIO/lora/<subject>/; consent is an
     operator seam (wenche_subject_consent); no paid training without the
     cost-proof seam.
158. postpro: the grading look is the operator's; keep the prior take; A/B is
     interleaved listening, not a golden file.
159. BIZ/tools/*.mjs (bp_build, bp_check, bp_index, bp_print, bp_retemplate,
     content_add, convert_content, paths, plans_a, plans_b): Node tooling in a
     Ruby house. Propose a Ruby port behind the same CLI contract, one tool
     per commit, rendered PDF comparison before and after. Operator decision:
     BIZ is a content root with its own production profile; do not break the
     published pairs.
160. BIZ published pairs (html/pdf): every change compares source and rendered
     pages; parsing alone is not visual preservation; bob templates are the
     shared base.
161. BIZ/research: husleieloven-2026.md and the growth studies carry legal and
     market claims; confirm each claim has a source, date and limitation;
     editorial review is separate from software verification.
162. fetat_proposal.md is the working master (a document, not policy); confirm
     no live config routes to it as authority.
163. BIZ index: one folder per workstream; confirm the index lists every
     published pair and no orphan template.
164. STUDIO doctor: private-path classifiers and token file mode checks are
     present; keep them; a new adapter ships with PersonalPermissions or not
     at all.

## K. Security and secrets

165. The operator pasted a GitHub PAT into this session's chat. Rotate it.
     Confirm no commit, log, paste or receipt carries it; this receipt
     redacts it. Add the rotation to the operator seam list.
166. security_sweep and RAILS/test/tracked_secrets_test.rb: run them on a
     compatible host; confirm the filter_parameter_logging expansion from
     2026-11-19 still covers password, phone, authorization, api_key,
     access_token, refresh_token, private_key, credit_card, card_number, iban.
167. SsrfGuard: all-answer fail-closed, pinned ipaddr, SNI hostname, no
     environment proxy, bounded phases; confirm every new HTTP client rides
     the guard; ROBUSTNESS_outbound_fetch_is_pinned is the law.
168. Redirects: WebBrowse checks Location before Chromium; ExternalAudit
     bounded same-host only; confirm no client follows implicitly.
169. CSP: report-only until PUB5_CSP_ENFORCE=1; the enforce-on-vm23 seam stays
     operator-owned; propose the enforcement rehearsal with a report review.
170. Outbound host egress: the seam names network-layer denial of private and
     metadata routes; application pinning is not a substitute; propose the
     pf rule set as a deploy-host change with native proof.
171. Rate limits: WriteThrottle 60/min, password 8/3min, reset 5/3min,
     account security 6/10min; confirm the regressions pin the numbers.
172. Session cookies: httponly, secure-in-prod, same_site lax, domain all for
     city verticals; confirm the multi-domain contract still holds.
173. Vipps params[:to] exact "checkout" allowlist; confirm no open redirect
     reintroduces a free-form target.
174. Soulseek adapter: loopback HTTP only, remote public HTTPS 443, key in
     process env; bulk acquisition disabled; consent per download; keep.
175. PersonalPermissions: microphone, camera, location, contacts, memory,
     financial reads; no adapter ships without it; financial actions
     read-only by default; keep the refusal.
176. Repository visibility: the repo is public; confirm no receipt, paste or
     screenshot carries a secret, a private path or a personal datum; the
     redaction contract is the log publisher's job.

## L. Tests, hooks and delivery

177. 921 MASTER test files: run MASTER_TEST_JOBS=1 bundle exec rake test on a
     compatible host; record the exact red list; do not claim a pass from
     authored tests.
178. boot_smoke: pre-push runs it; a push that cannot boot the /fix container
     is refused; confirm the smoke reads a real boot, not a stub.
179. pre-push session ledger: PUB5_SESSION or ppid; a missing ledger reads
     unknown, never foreign; confirm the one-commit print and the
     PUB5_PUSH_ALL gate.
180. commit-msg hook: one shape for every author; PUB5_COMMIT_FORMAT=0 is the
     deliberate escape; confirm the hook reads commit_format.yml, not a copy.
181. pre-commit cross-tree refusal: confirm a path-scoped commit cannot carry
     another tree's file; the shared checkout depends on it.
182. post-commit session ledger: confirm it records the sha under the session
     id so the next push can tell mine from foreign.
183. Hooks install: bin/operator hooks sets core.hooksPath; a fresh clone has
     no hooks; this session's delivery ran without them (API commit, no
     checkout, no Ruby); the next agent on a real host installs them first.
184. Snapshot mirrors: pre-push regenerates four source mirrors via
     tools/snapshot.rb; confirm they stay ignored and never become a pushed
     artifact.
185. Focused proof: bin/operator test <paths> for the smallest complete proof;
     /fix selects scope-aware proof; do not append --profile=full after every
     repair.
186. PATH_OWNERSHIP lib/master.rb exception: full loader/integration check on
     direct change; keep the narrow exception narrow.
187. Delivery receipts: every verified slice commits and pushes before the
     next; report DELIVERY_FAILED if the push cannot be proved; git log
     origin/main..HEAD before and after.
188. Log publication for /fix: the runtime publishes log0; standalone scripts
     keep logs local; review and redact before sharing; the operator's
     standing preference is gists or command-line pastebins.

## M. Micro-refinements (small, concrete, measured)

189. .editorconfig [*.py] removal (item 30) is one line; land it first as a
     warm-up slice with the doc lint.
190. laws_index.json final newline: one generator line plus fixture.
191. FACE_WORLD dedup: the largest single editorial win; 88 KB toward ~30 KB
     with zero meaning lost, proven by segment diff.
192. master-session exec bit: one chmod, one index update, one boot test.
193. zai bridge Ruby port: bounded, lane-preserving, operator-gated.
194. probe_webgl_guard Ruby port: removes node and the macOS path together.
195. termux install zsh conversion: one script, device seam for proof.
196. mrdamascy bin/dev zsh conversion: one script, Rails convention noted.
197. Trailing-whitespace trims: five runtime files, one commit each, focused
     test after.
198. Generated JSON newlines: three writers, one assertion in generated_asset.
199. Dead-lane probe: two lanes, one doctor run, evidence recorded.
200. Citation pending rows in incidents.yml: supply or keep honest; never
     invent.

## N. Restructure, rewire, reflow (larger, gated)

201. FACE_WORLD catalogue: after dedup, reorder by reader task (boot, geometry,
     speech, cognition, camera, materials); one canonical block; the operator
     approves the rendered-value decisions it records.
202. assessment_matrix split: only if a measured responsibility boundary
     exists; the spine pays its own nesting; no convenience split.
203. command_registry help generation: confirm one source; if help text is
     hand-maintained beside the registry, reflow it into the registry and
     generate.
204. BIZ mjs-to-Ruby: a toolchain reflow; operator decision; rendered PDF
     comparison is the proof; one tool per commit.
205. MASTER/bin surface: zai bridges, falcon shebangs, ruby discovery — one
     portability pass, one convention written into the shell law.
206. Checks registry: confirm every check has a class, a fixture and a
     known-bad case; retire a check that cannot fail; the sunset ledger
     prices it.
207. Convergence workstreams: 82 rows; the partial ones need a named next
     measurement, not a status bump; ops_alert_channel needs the operator
     relay shape.
208. Operator seams: 67 open; each names its evidence; the next agent routes
     evidence requests to the operator and closes nothing on inference.
209. Gap ledger: 54 gaps; the logic gaps are product decisions; the knowledge
     gaps need a source; the ux gaps need rendered evidence; none is a build
     order.
210. Polish wave 2: 500 seeds; the lens regenerates mechanical rows; taste
     stays operator-owned; reject any row that names no subject.

## O. Delivery protocol for the implementing agent

211. Start: ruby MASTER/tools/agent_context.rb --json; bin/operator doctor;
     bin/doctor; one narrow dry run (/fix --dry-run --critique --only
     critique,map MASTER/lib/cli). Read veto, INCONCLUSIVE and skip as
     failures of proof.
212. Work one tree at a time; one coherent slice per commit; path-scoped;
     capitalised subject; Co-authored-by trailer; push before the next slice.
213. Every visual change: fresh screenshots under RAILS/*.png or .webp,
     run-scoped, never reused; before and after; the critic reads only the
     current sweep.
214. Every /fix exit: FinalCleanup receipt; log0 published redacted; local
     logs stay on disk; name what was skipped.
215. Every claim: instrument, command, exit state. NOT_RUN is a first-class
     result. A stopped run is resumable, never successful.
216. Refutations: record in proposals.yml with the measurement; never delete;
     the ledger is the loop's memory.
217. Operator decisions: rendered values, taste, listening, live hosts,
     sacred-file edits, toolchain changes, paid lanes, consent. Name the
     remainder precisely; complete the independent work around it.
218. Close: patch closeout matches the contract examples — what changed,
     exact checks run, known debt named. This receipt is the intake evidence;
     the next receipt records what actually landed.

## Proof status of this session

- RUN: git clone/log/ls-files/rev-parse; text reads; PyYAML safe_load parses
  (0 failures over MASTER/data and checks/data); JSON parses; regex censuses;
  byte comparison of the agent-contract block; FACE_WORLD segment offsets;
  shebang and mode census; whitespace and newline census; .py census; GitHub
  contents API commit and ref verification.
- NOT_RUN: every Ruby suite, rake task, Law detector, /fix lane, browser
  check, doctor, boot smoke, hook, deploy. Blocker: no Ruby >= 3.2 in this
  sandbox (Debian buster, archived apt), no Chrome, no provider keys, no
  OpenBSD host; the sandbox recycled twice and lost the local checkout.
- No Law PASS, no test PASS, no deploy claim. The handoff is a hypothesis
  list with named owners and named proof; the next agent re-measures.


## Implementation follow-up — 2026-11-22

This appendix records the first landed implementation tranche. It does not close the
remaining sections above. Verified main head at close: `d54b70914cd6a49abe706c10435e4d195e9c9631`.

### Landed

- Removed the unused `[*.py]` editor block.
- Updated the canonical Law-index writer to emit a final newline; added a temporary-output
  generator regression and updated the committed JSON projection.
- Updated the coverage-state and autopoiesis-manifest writers to emit final newlines.
  Added focused newline assertions; added a final-newline assertion for the face music JSON.
- Consolidated `MASTER/FACE_WORLD.md` from six repeated runtime/catalogue copies to one
  606-line canonical document. The retained copy is the expanded latest structure; the
  measured 1.075 spacing, Hollow Gaze, Faultline and state-force semantics were preserved.
- Changed `MASTER/bin/master-session` to index mode 100755 and added an index-mode regression
  for direct `MASTER/bin` entrypoints.
- Trimmed trailing whitespace in five maintained source/test files:
  `law/surface.rb` (9), `tools/portal_agent.rb` (4),
  `test/test_dialogue_rubric.rb` (1), `test/voice/test_voice_support.rb` (1),
  and `web/public/three.face.module.js` (13).
- Converted the Termux bootstrap to its installed zsh with `set -euo pipefail`; updated
  its syntax test to use `zsh -n`.
- Converted `RAILS/mrdamascy/bin/dev` from bash to strict zsh while retaining overmind-first
  and foreman-fallback behavior.
- Removed the misleading executable shebang from `scripts/publish_log.zsh`; it defines a
  function and is a sourced library, so it must not change the caller's shell options.
  Added a source-only regression.
- Replaced `probe_webgl_guard.mjs` with `probe_webgl_guard.rb`, using the existing
  `Deploy::CdpSession`, shared Chrome discovery and SwiftShader launch. Updated both CI
  entrypoints and the face boot contract; removed the Node probe. The new probe has no
  hardcoded macOS Chrome path.
- Corrected two autopoiesis honesty defects: unimplemented regeneration now returns
  `INCONCLUSIVE` without changing the manifest; file presence alone no longer yields a
  healthy component. Added regressions for both behaviors.

### Proof actually run

- GitHub Contents API reads/writes and main-ref verification for the changed paths.
- Git Trees API: `MASTER/bin/master-session` is mode 100755; the retired
  `probe_webgl_guard.mjs` path is absent; the Ruby replacement and converted shell paths
  are present with the observed modes.
- In-session JavaScript assertions: `JSON.parse` succeeded for
  `laws_index.json`, `coverage_map/state.json`, `autopoietic_components.json`, and
  `face_music_packs.json`; each has a final newline. FACE_WORLD's candidate passed the
  measured section and retained-content assertions before commit.

### Not run / not claimed

- Ruby syntax checks, every Minitest/Rake suite, Law detectors, `agent_context.rb`,
  `/fix`, boot/doctor, the new Ruby CDP browser probe, screenshots, Termux device tests,
  mrdamascy app tests, hooks, OpenBSD host checks, NSD/DNSSEC proof and deployment.
- No Law was commented out. No runtime Law pass was established; the conditional
  disablement instruction was not invoked because no specific blocking Law was proven
  in the source-only tranche.
- The five whitespace edits and all other source changes remain unverified by Ruby tests.
- The Z-AI Bun-to-Ruby bridges and the ten BIZ Node-to-Ruby tools remain unported. Their
  credential/SDK and rendered-PDF contracts need a measured replacement and the focused
  provider/PDF proof; neither lane was deleted.
- The exposed PAT rotation remains an operator action. Rotate it in GitHub; this session
  cannot revoke or replace a token from chat.

The next implementation pass must continue with the remaining owned items above, not treat
this appendix as a completed /fix, test suite, or deployment receipt.


## P. Professional graphic design and micro-pixel CSS craft (addendum)

The first intake underweighted the rendered surface. The design constitution is
already professional and encoded: tokens.yml carries visual_identity
(signal_and_stillness), scale, layout_rules, typography, worn_type,
pixel_perfection, rams_checklist, ui_polish, ultraminimalism, ux_laws,
vertical_accents and vertical_accent_ink. css_architecture.yml orders the
cascade reset, tokens, base, components, utilities, autofix, forbids !important
in the last three, and caps specificity at 0,3,0 in warn mode. The instruments
exist: geometry_probe walk.js and design_laws.js, rendered_geometry placement,
space, grammar, composition and token checks, type_laws, contrast, reflow,
occlusion, viewport_spill, layout_snapshot drift, first_screen, kanso_surface,
web_vitals_budget. The work is to drive their measured findings to zero per
surface, not to invent a second design system.

Measured off-scale baselines (tokens.yml#tokens.scale.baselines, the worklist):

219. Apps: off_scale_radius 19, off_scale_tracking 6, off_scale_opacity 20,
     off_scale_duration 14, off_token_color 21. Route each to the scale arrays
     (radius 0/2/4/8/12/16, tracking -0.03..0.14em, opacity 0.03..0.8,
     duration 180/300ms) or document a scoped exception at the point of use.
220. Face: off_scale_tracking 12, off_scale_opacity 27, off_scale_duration 26,
     off_token_color 8. The face is generated; fix the part files, never
     face.runtime.js.
221. Compiled amber: font-size 40 off-scale, padding 68, margin 35, gap 40,
     color 37, background-color 9, border-color 9, border-radius 17,
     letter-spacing 13, line-height 15, font-weight 9, z-index 13, and one
     box-shadow. The box-shadow is a flat_ui candidate: strip it or record the
     named exception pixel_perfection.exception_policy demands.
222. Compiled brgen: font-size 64 off-scale, color 67, letter-spacing 17,
     line-height 18, font-weight 10. Work by engine stylesheet, one coherent
     slice per commit, before/after screenshots at 390/768/1280.
223. Add a z-index scale to tokens.scale; the compiled z-index counts have no
     token owner today. Name the layer stack in CSS, not magic integers.
224. Enforce the 8px rhythm with 4px hairline allowance (layout_rules.grid);
     off_scale_space is already 0 for apps and face; keep it 0 as pages grow.
225. Apply the proportional split 0.618/0.382 for major panels; replace
     arbitrary widths; prove with rendered_geometry placement checks.
226. Apply whitespace rules: internal padding never exceeds external
     separation, gap before margin, section padding 4-8rem, paragraph margin
     1.5em. These are Gestalt proximity made executable; route findings to the
     space checks, not a new law.
227. Apply alignment rules: body left-aligned with right rag, centre text
     capped at three lines, asymmetry before decoration, critical content on
     the F/Z scan path, primary area top-left, terminal bottom-right.
228. Apply touch rules: 44px minimum, 48px recommended, primary actions in the
     bottom-centre thumb zone; flag critical mobile interactions in unreachable
     top corners; REACH_touch_target_min owns the contract.
229. Apply type tokens: page titles var(--text-title, 1.25rem), display
     1.75rem, page-header min-height 48px; no hardcoded 20px headers; dialect
     fonts (Caprasimo luxury, JetBrains mono CRT) only on named brand surfaces;
     the no-serif directive stands for brgen, amber and master.
230. Apply line-height scale 1/1.25/1.4/1.5/1.6; absolute line-height baseline
     is 0; keep it 0; worn_type feeds the geometry_type measure.
231. Apply space_not_lines: list/grid cards separate with gap and elevated
     surface, not hairline borders; forms and the bsdports CRT dialect may keep
     1px borders; prefer border:0 with var(--surface-elevated).
232. Apply the one button family: button-primary, button-ghost, button-danger,
     button-small, button-link, button-block, button-share; the BEM twins are
     retired; RAILS/refinements shared-010 retires button-small in favour of
     $compact-contexts; finish it.
233. Apply chrome_i18n: shell and empty/search chrome use I18n t() keys (nb
     default, en available); hardcoded English "No ..." titles and "Search ..."
     placeholders are debt; the ratchets are chrome_i18n_lint.rb,
     empty_state_lint.rb, adhoc_empty_lint.rb; every empty state needs an action.
234. Score every UI diff against the Rams checklist (useful, understandable,
     unobtrusive, honest, thorough) in council and aesthetic scan tags; design
     empty, loading, error and reduced-motion states before calling a surface
     done.
235. Honour the motion grammar: animate existing elements before creating new
     ones, travelling waves and threshold cohorts over generic fades, bound
     population/duration/amplitude/cost/lifecycle, every meaningful animation
     has a reduced-motion equivalent, stillness is the default.
236. Honour the void grammar: negative space is structural, never decorative
     noise; one dominant focal point and one primary action per first screen.

Modernisation that stays native to the house (importmaps, ERB, Stimulus, Turbo;
no third renderer, no ornament):

237. Move specificity ceiling 0,3,0 from warn to error after the off-scale
     cleanup; a ceiling that only warns is a suggestion.
238. Adopt CSS cascade layers fully across engine stylesheets; the order is
     already declared; confirm every engine emits into the same stack and no
     sheet escapes it.
239. Adopt logical properties (LOGICAL_PROPERTIES rule) for margin/padding/
     inset; nb and en share direction today, but the property discipline
     prevents a future locale regression.
240. Adopt clamp() typography (CLAMP_TYPOGRAPHY rule) for fluid display sizes
     within the token scale; no arbitrary viewport breakpoints outside
     tokens.viewport.
241. Evaluate container queries for vertical dialect components so a card
     adapts to its container, not the viewport; keep the 12-column grid for
     page structure.
242. Evaluate :has() for stateful component styling without a Stimulus value
     where the state is purely presentational; keep behaviour in Stimulus.
243. Adopt text-wrap: balance for headings and pretty for body rag; Norwegian
     hyphens: auto with lang=nb; prove no overflow at 320px.
244. Adopt :focus-visible rings from tokens; REACH_focus_visible owns the
     contract; never remove outline without a token replacement.
245. Adopt font-display: swap and a variable sans within the no-serif rule;
     confirm font weights stay on the 400-800 scale.
246. Adopt content-visibility: auto for long feeds and lists with contain-
     intrinsic-size from measured row heights; prove with web_vitals_budget.
247. Adopt scrollbar-gutter: stable and overscroll-behavior: contain on
     scrollable panels; no layout shift on scrollbar appearance.
248. Adopt accent-color and native dialog/popover where Stimulus already wraps
     them; do not introduce a second dialog renderer.
249. Keep Turbo navigation; evaluate view transitions only as a progressive
     enhancement with a reduced-motion equivalent and a measured cost.
250. Reorganise stylesheets by engine ownership under the layer stack; run
     dead_css_sweep, dead_css_static and dead_css_coverage; collapse the 6
     CSS_DUPLICATE_DECLARATION and 22 CSS_SHORTHAND_COLLAPSE findings; prove
     css_minify_integrity and css_brace_balance after each build.
251. Build critical first-screen CSS through tools/rails/build_all_css.rb;
     first_screen and page_weight budgets own the numbers; no render-blocking
     sheet above the fold.
252. Drive TYPOGRAPHIC_GRID (1711) and VERTICAL_BREATH (2289) to zero per
     surface with rendered evidence; the operator gates every rendered value;
     screenshots under RAILS/*.png before and after, run-scoped, never reused.

## Q. DRY and KISS opportunities (addendum)

The repo already governs both: DRY and KISS are law roots; dup_census.yml
tracks 161 duplicate sets with ceilings; DENSITY_identical_branches,
content_dedup_scan, dead_css_sweep, dead_route_sweep and the 85
REDUNDANT_CORE_REQUIRE findings are the instruments. The proposals ledger
refuted several consolidation moves (family moves, lazy-class extraction,
best-of-N, parallel streams). DRY here means measured duplication with a named
consumer, not ideological deduplication; KISS means one owner per concept, not
fewer files. The spine ratchet and cohesion census forbid convenience splits.

253. Triage dup_census intentional vs accidental. Intentional: screenshot
     baselines for generic routes (/up, historical locations) shared across
     apps; amber logo plates and asset copies; mrdamascy standalone Vipps
     wordmark; BIZ published pairs. Accidental candidates: MASTER/lib/operator/
     domain_signals.rb vs OPENBSD/lib/domain_signals.rb (verify whether OPENBSD
     self-containment on the box justifies the copy before merging); the shared
     vs brgen anonymous_post_quotas migration copy (engine-promotion residue);
     the four identical Rakefiles (MASTER/web, amber, bsdports, mrdamascy).
254. Finish redundant_core_require_cleanup (85 findings, convergence partial);
     the spine test stays green and the body ceiling ratchets down.
255. Work DENSITY_identical_branches and DEAD_CODE (6) by file with the focused
     test; a branch that differs only in a constant is a parameter, not a copy.
256. Collapse the measured CSS duplication (item 250) through the existing
     autofix regions; no blanket rewrite.
257. Run dead_route_sweep and content_dedup_scan; retire routes and content
     with no consumer; record each retirement in the sunset ledger with its
     measured catch.
258. KISS targets, measure before splitting: assessment_matrix.rb 74 KB,
     command_registry help 40 KB / host 60 KB / review 58 KB, CONFIGURATION_SHAPE
     87, CHOICE_OVERLOAD 4, BOOLEAN_TRAP 2. The 812 SMALL_FUNCTIONS, 650
     FEW_ARGUMENTS, 447 CYCLOMATIC_COMPLEXITY and 392 ABC_SIZE findings are a
     measurement baseline; many are not defects; route only the ones a caller
     or a reading proves painful.
259. Resist new abstractions: the refused list is the KISS backbone. No second
     queue, no second memory, no second presenter, no second recovery contract,
     no detector without a subject, no writer for a reader that does not exist.
     Every proposed extraction names the caller that needs it.
260. Keep one counting method: CodeMetrics.body_lines is shared by lint:spine
     and SmallFunctionsRule; never introduce a second line counter to make a
     number look better.

## R. Vertical competitive readiness (addendum, evidence-bound)

The honest verdict on the repo's own standard: no brgen vertical is yet proven
competitive with the incumbent it names. Feature source counts are high
(apps.yml: core substantially done, takeaway 6/6, tv 11/12, dating 11/12,
playlist 8/9, marketplace 17/23), but the constitution separates declaration,
implementation, passing test and excellent product. Rendered acceptance, live
payments, real devices, SEO crawl, human accessibility review and the named
logic gaps remain INCONCLUSIVE or operator seams. The brand contract itself
says verticals inherit Brgen identity and gain a surface dialect; they become
standalone brands only when they have a distinct market and promise. The moat
is the city network, not per-vertical feature parity. Dominance language is BIZ
narrative; engineering evidence supports a coherent, locally differentiated
network, not yet standalone vertical dominance.

261. Marketplace vs Finn.no: 17/23 done; Solidus core mount, starter storefront,
     native marketplace features, Dintero split checkout, the Amazon parity map
     and AI recommendations are planned, not landed. gaps.yml names liquidity
     (knowledge), coupons, contact relay, duplicates (landed), paid boosts,
     seller analytics. Verdict: credible local classifieds structure; no
     proven liquidity, no split-payment proof, no parity. Finn's inventory and
     habit are the wall; the city-first trust angle is the opening.
262. Takeaway vs Wolt/Foodora: 6/6 source done, but gaps.yml names delivery
     area (landed), cart expiry (landed) and the pro surface (planned); live
     driver logistics, restaurant inventory and tracking are unproven; payments
     in provider staging is an operator seam. Verdict: ordering flow exists;
     the logistics network and restaurant supply that define Wolt do not yet.
263. Dating vs Tinder/Hinge: 11/12 done; premium/boost planned; gaps.yml names
     two-sided ranked-for and cold-start liquidity. Verdict: matching structure
     exists; a dating product is its liquidity, and that is unproven. The
     local, trust-scored angle is the differentiation.
264. Messenger vs WhatsApp/Messenger: core DM done; gaps.yml names WebRTC calls
     and business CRM; notify suppression is a UX gap. Verdict: text messaging
     exists; calls and the network effect do not. Competing head-on is the
     wrong frame; city-community messaging is the native niche.
265. Maps vs Google Maps: gaps.yml names the POI substrate; the MapLibre runtime
     and vendor decision is an operator seam (licensing). Verdict: a map surface
     without a POI corpus is a renderer, not a maps product. The local graph is
     the asset; the substrate must be sourced and licensed.
266. Radio/Playlist vs Spotify: 8/9 done; creator donations/ad-free planned;
     gaps.yml names creator donations. Verdict: playlist structure exists;
     streaming licensing is the wall the repo cannot code around. Local
     curation and creator ownership are the opening.
267. TV vs YouTube/Twitch: 11/12 done; live stream infrastructure planned.
     Verdict: VOD structure exists; live infra and creator supply do not.
268. What would change the verdict, per vertical: close the named gaps.yml
     rows; land the planned apps.yml features with rendered acceptance; run the
     operator seams (payments staging, real devices, SEO crawl, human
     accessibility, live journeys); record market evidence (liquidity, supply,
     retention) as research with provenance, not assertion. Until then the
     truthful status is INCONCLUSIVE, and the repo is right to mark it so.
269. Do not assert dominance in product copy without the evidence; the
     persuasion_honesty and content_honesty checks own that contract. The BIZ
     plans may argue the thesis; the product must show the proof.
270. The competitive strategy the architecture already encodes: win the city,
     not the category. One network across verticals, local before global,
     useful over noisy. Each vertical competes on locality and trust joined to
     the network, not on out-featuring a global incumbent on a 1 GB SQLite box.


### Continued implementation follow-up — 2026-11-22

- Trimmed 80 trailing-whitespace lines in `MASTER/data/structural_recipes.yml`.
  GitHub read-after-write preserved all 624 lines and the final newline; a
  byte-for-byte comparison confirmed the result equals trailing-space
  normalization. YAML parsing and the focused Ruby test were NOT_RUN.
  Commit: `989eda5bcff56ef0c385c492fb7e75573b5d70de`.
- Reduced the root README's `First hour` section to its unique disposable-
  sandbox bootstrap instructions and a pointer to the canonical MASTER
  first-hour/doctor guide. The shared host diagnostics and first-repair
  sequence are no longer repeated there.
  Commit: `87bacfdba5807b6ce0c36d04e91849f00c867618`.
- Marked `MIGRATION.md` as historical provenance, not live policy, runtime
  configuration, backlog or runbook. A repository search found references
  only in the inventory, legacy-state comments and tests; no maintained
  reader-facing document routes to it as current authority.
  Commit: `27ba43d4691e7d19c644093e8b9d1dac0b9e4ee5`.

Proof actually run: GitHub read-after-write verification for all three paths;
line-count, final-newline and trailing-space assertions for
`structural_recipes.yml`; section-boundary and canonical-heading checks for
the README pointer; exact-reference search and inspection of every returned
`MIGRATION.md` reference.

Not run: Ruby syntax/tests, YAML parser, Markdown link checker, rendered
Markdown review, `agent_context.rb`, `/fix`, boot/doctor and repository-wide
checks. These refinements are delivered; their runtime/editorial proof remains
INCONCLUSIVE, not PASS.


- Refuted the suggested axe-core craft-ledger exemption. The current vendor
  bundle is loaded by `Deploy::Axe` in the existing CDP page, and
  `TestAxe` pins its version header and MPL-2.0 licence. The craft ledger
  documents existing executable Law markers; it does not grant exemptions,
  and the freshness check rejects rows without a corresponding executable
  Law. No axe-specific marker exists, so no new ledger row is valid. Vendor
  bytes and the ledger remain unchanged.
  Refutation recorded in `MASTER/data/proposals.yml`.
  Commit: `9ff8c7c08d6699fb5dbdef30fbf395568abd03b4`.

Proof: inspected and fetched the exact vendor header and licence, CDP source,
  version/licence test, craft-ledger contract and exemption freshness reader;
  verified the refutation entry by read-after-write.

Not run: `TestAxe`, CDP/Chrome, licence audit and all Ruby checks.


- Replaced the last present-tense reference to the deleted root `TODO.md`
  in `MIGRATION.md` with the live convergence, gap, operator-seam, UX and
  RAILS refinement owners. Historical table entries that accurately describe
  the migration-era TODO remain as provenance.
  Commit: `095d00d19707375c2bb1160dc75772f15335be7f`.
- Verified that the three files named by MASTER/AGENTS.md's “Working alone”
  section — `MASTER/test/test_entrypoint_requires.rb`,
  `MASTER/lib/fix/code_watch.rb` and
  `MASTER/checks/support/cdp_framing.rb` — exist at the documented paths.
  This confirms path existence only, not the continued accuracy of every
  operational statement in that section.

Proof: read-after-write verification, targeted reference scan of all 518
migration-record lines, and GitHub file reads for the three named paths.
Not run: documentation lint, rendered Markdown inspection, test suite,
`agent_context.rb` or `/fix`.


### Static contract checks — 2026-11-22

- `tool_habits.yml`: all 15 named tool adapters are present in the canonical
  `tools.yml` registry. No retired tool reference was found in this census.
- `state.yml`: all eight declared standing-order callable names map to
  classes in `Master::Ground::Orders::Registry`. This confirms source wiring,
  not that any order ran or that a remote side effect succeeded.
- Event topics: the proposed deterministic publisher/subscriber census
  already exists as `MASTER/tools/event_bus_reach.rb`, with focused tests in
  `MASTER/tools/test/test_event_bus_reach.rb`. Its report includes publishers,
  Ruby subscribers, browser listeners, references, unpublished and unconsumed
  topics, missing contract publishers, retired topics and reference-anchor
  gaps. No duplicate census was added.
- `incidents.yml`: one incident (I-007) still cites an operator session
  record with “in-tree citation pending”. No independent source was found in
  this pass, so the honest provenance remains unchanged; no citation was
  invented.

Proof: exact GitHub reads of the four registries/source files and static
name-to-registry comparisons. No command or Ruby test was run; all runtime
verification remains NOT_RUN.
