# pub5 — remaining work

Audit baseline: 2026-11-11, source tree checked against `main@ff60792298f5d654cc7976fd9dfb3b8d4393d786` (complete tree `823a0dc917d01a4ffbb986de93fa27492e543b0d`).
Snapshot: 169 unchecked register rows and 1 checked row (grouped rows are not
atomic task counts). The tracked tree contains no `PLAN.md`; root `TODO.md` is
the sole cross-tree Markdown action register, with detailed state owned by the
existing structured ledgers. No parallel plan or backlog file is needed.
The register travels with the migration; source-owned status remains in the
structured ledgers, and completed entries are checked here only when their
evidence is present.

Follow-up audit: pub4/main remains at the recorded migration cutoff; the live
blob disposition is refreshed in `MIGRATION.md` against `ff607922`. The
execution container has Ruby 3.3.8 but no repository checkout; a shallow clone
failed at DNS resolution for github.com. Repository test, lint and build commands
therefore remain NOT_RUN in this session. Subsequent source and regression-test commits were pushed through the repository API after source review, but could not be executed through `bin/check`; their current-revision status is NOT_RUN, not PASS. They remain pending acceptance on the installed compatible Ruby. PRs #11 (MASTER portrait,
semantic subject morphs, CLI feedback and Replicate upload guards) and #12
(Brgen city wordmark refinement) are merged. No pull request was open at the
time of this audit. Entries below remain open until their own source, test,
rendered or external evidence is actually recorded.
This register replaces the previous 1,275-line, 462-checkbox carry-forward
dump. It contains unresolved outcomes, not session notes or speculative
architecture proposals.

## Stewardship

Documentation reduction and decisive stewardship remain priorities one and two.
Keep one canonical instruction at each real boundary; remove duplication before
adding a registry, wrapper or document. Add no Markdown files for backlog
administration.

When an authorised request overlaps an item below, do the work now and remove
the item when its evidence is committed. Add no TODO for work available with
current tools, credentials and authority. Keep only genuine unresolved work
and external prerequisites. Continue independent work when one item is blocked.

A source change, authored test, passing test, full suite, rendered product and
live deployment are different claims. Record revision, command, exit status
and evidence. Use PASS, FAIL, INCONCLUSIVE, BLOCKED, NOT_RUN, TIMEOUT or
DELIVERY_FAILED truthfully. Never infer PASS from a declaration, commit,
screenshot count or previous revision.

## 1. Current-revision acceptance

- [ ] **MASTER on the installed compatible Ruby.** Run focused Law, Soul, configuration,
  registry, replay-reader, fix-loop oscillation, reachability, run-ledger,
  media and CLI regressions. Then run
  `MASTER_TEST_START_MARKERS=1 MASTER_TEST_JOBS=1 MASTER_TEST_PROGRESS_EVERY=25 rake test`,
  `MASTER_TEST_JOBS=3 rake test`, `rake audit` and
  `bin/check --profile=agent`. Inspect
  `.master/check/suite-report.json` for incomplete workers and mismatched
  start/result counts. Preserve actual output.
- [ ] **RAILS full contracts on one current revision.** Run
  `ruby RAILS/test/run_all.rb`, every app's `bin/ci` and
  `ruby MASTER/checks/runner.rb --all`. The last recorded RAILS run had six
  red checks: CSS budgets, file-length and method-length ratchets,
  `studio_contract` (possibly a stale diagnosis), viewport spill, and live
  locale/layout checks against old servers. Reproduce against fresh servers
  and current migrations; fix confirmed defects rather than suppressing
  findings or raising ceilings.
- [ ] **RAILS focused gaps.** Run billing, API-key/API-lint, dating identity,
  Radio manifest/TrackImport, share and job-concurrency, Amber account-merge,
  Marketplace filter/card/mutation, Takeaway model/migration, empty-state,
  token-projection and design-token tests. Use fresh databases; verify both
  fresh-install and upgrade migrations where applicable.
- [ ] **OPENBSD updated runner and native proof.** Previous evidence was
  45 files/0 red, rehearsal 16/16, PF policy 11/11 and evidence tool 9/9.
  The runner now rejects empty or invalid Minitest summaries and has new
  regression tests. Run the updated `ruby OPENBSD/test/run_all.rb` and
  runner tests; on actual OpenBSD run `pfctl -nf /etc/pf.conf`.
- [ ] **STUDIO full proof.** Earlier `rake check` and Dilla test
  (17 runs, 386 assertions) passed. The strict per-file runner now forwards
  keyword and positional subprocess environments correctly and rejects empty
  or invalid Minitest summaries. Its new subprocess regressions are source
  coverage, not a passing run. Run `cd STUDIO && rake check test` on the installed compatible Ruby (3.3+). Review an actual Dilla render by ear with rights-cleared local
  source and confirm the sample level leaves voice room.
  2026-11-07: `rake test` ran green — 7 files including the new
  `test_dilla_wear_test.rb` (Sonitex wear-pass battery; three Dilla rig
  capabilities promoted in the analog capability contract). The by-ear render
  review remains.
  2026-11-07, later: `rake check` answers and `rake test` ran green across
  11 files, adding the crush, sidechain, loudness and groove batteries —
  seven Dilla rig capabilities are now promoted with counted proofs (mpc
  twelve-bit grid, the 10 ms staircase sidechain, the delivery loudness
  ceiling, the pocket micro-timing), `steer_to_reference!` left the render
  body as a nameable method, and the MPC swing map now lands 66 percent
  exactly on the triplet as its own comment documents. The by-ear render
  review remains.
  2026-11-08: Replaced the Python/NumPy/SciPy reference analyzer with
  `STUDIO/dilla/lib/reference_analyzer.rb` (WAV decode/resample, FFT, tempo,
  onset/pocket, mix-band energy, key/chord, melody and drum-grid analysis).
  Removed the only tracked STUDIO `.py` source and Dilla's Python/Demucs
  runtime fallbacks. Reference acquisition and local renderer subprocesses
  now have explicit wall-clock bounds; output writes preserve prior files on
  failure. Added the `bin/studio ableton inventory|export|midi` route and
  regression coverage for CLI dispatch, analysis bounds and renderer timeout.
  A separate local Ruby 3.3.8 synthetic 86 BPM WAV check measured 86.13 BPM;
  it is not a run of the committed Studio suite. These new/changed tests are
  NOT_RUN on the pinned Ruby 4.0.5 checkout. The by-ear render review and
  golden audio fixture remain open; no claim of acoustic acceptance is made.
  Set-specific Ableton recovery remains deliberately deferred until the
  operator supplies the `.als` sets and their project assets. The Dilla voice
  brief now surfaces the existing source-backed timing, form, classical
  lineage and Donuts sample-reference records while stating that the empty
  chord arrays still need real transcription; two direct MASTER regressions
  cover the brief and the five canonical grammars/six voicing guides. The
  Replicate client now has streamed JSON caps and monotonic bounded prediction
  and training waits, with seven transfer/deadline tests added. All these new
  and changed tests remain NOT_RUN on pinned Ruby 4.0.5; no golden WAV, actual
  listening verdict, ALS-set check or live provider transaction is claimed.

- [ ] **Generated-output freshness.** Check design-token projection and CSS;
  compare `MASTER/web/public/face.runtime.js` and `face.css` with their
  sources; run `cd MASTER && rake docs:agent_contracts` and
  `rake lint:agent_contracts`. Run
  `ruby MASTER/lib/operator/self_findings.rb --ratchet` after source changes
  settle; review member deltas and ensure neither ceiling rises.
- [ ] **Law and Baymard gates.** Run `rake lint:law_parity` and
  `rake -f MASTER/Rakefile ux:baymard` on the installed compatible toolchain. The Baymard
  regression file previously ran 24/24; the full report remains unverified.
  Keep unmeasurable surfaces INCONCLUSIVE and reuse existing Law identities.

## 2. MASTER /fix convergence and recovery

- [ ] Run `MASTER/test/test_fix_interruption_restart.rb` on the installed compatible Ruby.
  Verify interruption, rollback, durable mission resumption, orphaned
  Kernel-receipt recovery and checkpoint survival. Then exercise budget and
  collapse behavior, zero-repair ledger honesty and adapter receipt parity.
  Source refinement: `Kernel#run(adapter:, contract:, ...)` is now the public
  validated gateway; the convergence adapter supplies a conservative,
  target-scoped compatibility contract only for older callers, and the
  coordinator start receipt records its contract digest. The existing
  `OutcomePolicy`, `Execution::Contract`, `LifecycleJournal` and assessment
  artifacts remain canonical; no parallel six-term enum or TerminalReceipt
  hash chain was added. Council violation and improvement critique budgets are
  clamped to the actual remaining pass deadline. Focused gateway, contract and
  Council regressions are authored but NOT_RUN.
- [ ] Run one genuine repository-wide `/fix` over MASTER, RAILS, OPENBSD, STUDIO and
  BIZ. Preserve four independent reports, grounded candidates, revision,
  receipts and truthful terminal states (DONE, PLATEAU, HUMAN_DECISION,
  BLOCKED, VALIDATION_FAILED, DELIVERY_FAILED or TIMEOUT). Measure actual
  convergence and repair quality; an architecture map is not runtime proof.
  A first unattended intake slice now exists behind
  `MASTER_BACKLOG_AUTORUN=1`: it selects only mechanical, single-tree rows
  with exact paths, queues one durable Mission, and reuses TaskSteward and the
  existing /fix pipeline. Terminal delivery receipts require a completed
  Mission, non-empty summary, current source item and zero pending repository
  writes. The closed ProofMap v2 maps known test, lint/audit, visual,
  accessibility and runtime commands to TaskContract proof types. The executor
  runs only argv-allowlisted commands and records command/output digests, exit
  status, working directory and duration; unknown commands remain ineligible.
  Scope intake refuses symlinked path components, hard-linked files and
  noncanonical relative paths. Dependency-aware scheduling across structured
  owners, broader acceptance-command coverage beyond the current allowlist and
  automatic root-checkbox reconciliation remain open. These runtime paths
  still need their authored regression suites run on the selected repository
  Ruby.
  Human, rights, provider-spend, device and production-host approvals remain
  real stop points. Build on these existing owners; do not add a second queue.
- [ ] Verify shared-checkout lock, writer ownership, interruption cleanup and
  path-scoped commit behavior with another active writer. Never stage another
  writer's changes.
  
Build on existing Mission, Supervisor, TaskSteward, TaskContract,
OutcomeLearning, RepairMemory, RunBudget, RunPulse, Transaction and
Checkpoint owners. Do not create a YAML backlog, second proposal system,
second push path or duplicate orchestration to make TODO.md machine-readable.

## 3. Interaction, rendered UI and accessibility

- [ ] **400-case interaction campaign.** The last audit counted 400 cases:
  8 mapped adapters and 392 unmapped. Add exact action/fault tests with
  isolated state and saved evidence. Do not map unrelated tests or use generic
  page-load assertions. Run
  `ruby MASTER/tools/rails/premerge.rb --interactions`; SKIPPED/BLOCKED
  cases must keep the gate non-green.
- [ ] **Rendered review.** The 2026-11-03 sweep captured 181 pages, 1,751
  screenshots and 697 dialog states with zero capture failures. Review the
  captures, reach the 64 parameter routes missed by the guest sweep (mostly
  signed-in states), and inspect keyboard-only use, 200% zoom, forced colours,
  reduced motion, focus and responsive overflow.
- [ ] **Accessibility.** The computed Chrome AX-tree check samples at most
  two surfaces per app and viewport. Expand only after measuring cost. Keep
  VoiceOver/NVDA announcement tests and human assistive-technology sessions
  separate from automated AX-tree checks.
- [ ] **Human task evidence.** BLOCKED (2026-11-06): needs real, consenting
  participants and the operator's privacy review; no tool or agent may stand in.
  Original row: Collect privacy-reviewed, anonymised evidence
  for navigation, search recovery, product evaluation, cart costs, guest
  checkout/recovery, mobile completion, keyboard and assistive technology.
  Never manufacture participants or observations.
- [ ] **WebGL proof.** BLOCKED for Brgen Maps (2026-11-06): no MapLibre bundle
  is loaded at runtime (RAILS/test/marketplace_cart_contract_test.rb forbids the
  vendor and CDN bundles), so maps.brgen.no always renders the list fallback
  and there is no clustering to verify; needs the operator's decision to ship a
  MapLibre bundle (and its CSP). The fallback's layout was fixed in 295b462b3c.
  The BSDPorts half is still open. Original row: Verify Brgen Maps clustering in a real browser at
  mobile/desktop widths: cluster expansion, popups, search, cross-city links,
  keyboard/list alternative, failure fallback, context teardown and console.
  Run its focused Rails test. Verify BSDPorts' dependency graph in a real
  browser and run `cd RAILS/bsdports && bin/ci`; keep the text tree accessible.

## 4. RAILS product quality

- [ ] **End-to-end journeys.** Cover Brgen feed, posts, moderation, maps,
  Marketplace, dating, messenger, radio and takeaway, including authorisation,
  empty/error states, guest-to-account conversion and transfer/retry for every
  sign-in path.
- [ ] **Budgets and ratchets.** Re-measure CSS, JS and PWA from a fresh build.
  Last recorded CSS values were Brgen 289/217 KB, Amber 154/103 KB and
  BSDPorts 91/62 KB (measured/ceiling); refresh before choosing refactors.
  Re-run file/method length checks on current main and fix actual hot spots.
- [ ] **SEO/indexability.** Crawl canonical hosts brgen.no, ai.brgen.no,
  amberapp.art and bsdports.org; verify aliases amberapp.no, amberapp.online
  and bsdports.net. Include representative Brgen vertical hosts and city
  apexes. Record timestamped HTTP/redirect, robots, sitemap, JSON-LD and
  indexability evidence. Decide whether the MASTER face should be indexed.
  Reuse existing surface-schema and SEO checks.
- [ ] **Marketplace/Takeaway.** Run focused filters, cards, mutations, render
  and model suites; verify fresh and upgraded migrations; capture responsive
  browser evidence without changing existing listing rows or ownership.
- [ ] **Whyp/Radio.** Run the import-time Whyp resolver, TrackImport and
  Playlist view/controller suites on pinned Rails. Prove Radio tenant
  isolation, idempotency, ordering, checksums and failure atomicity. Do not
  import any of the 35 selected recordings until distribution rights are
  confirmed individually.
- [ ] **BSDPorts/empty states.** Run Solid Queue proof: enqueue a development
  job, verify its configured SQLite database and recurring jobs, inspect the
  jobs UI. Run empty-state source lint and focused Amber/Brgen views.
- [ ] **Tokens/face CSS.** Run
  `ruby MASTER/tools/rails/build_all_css.rb --check` and the design-token
  tests. Distinguish semantic constants (black canvas/print and OpenBSD
  wscons green) from replaceable presentation literals; regenerate face CSS
  and compare rendered pages.
- [ ] Close accepted `MASTER/data/law/ux_refinements.yml` rows only with their
  declared test, browser, terminal, accessibility or rendered-runtime proof.

### Screenshot-led micro-refinements (reviewed 2026-11-06 at `main@3fb7dbc`)

These are targeted findings from the committed RAILS desktop/mobile and
Mr. Damascy flow captures, not proof of the current live render. Reproduce
each in the existing Chrome/CDP suite before changing source; distinguish
seed, consent, loading and empty states from persistent layout defects.
Keep the product dialects, operator-owned palette/typefaces, canonical
tokens, and original marks intact. The Mr. Damascy item sheet, empty-cart
recovery, loyalty and offline screens already have clear, coherent states;
preserve those strengths.

- [ ] **Radio tunnel recapture.** The current playlist home now uses the full-screen
  tunnel, an explicit tap-to-start overlay, and a live track label; the November
  5 image appears to predate that surface. Recapture after the source change and
  verify the first-play, no-track and reduced-motion states before deciding
  whether an empty/loading treatment is still missing.
  Laws: `TRUTHFUL_STATUS`, `WAITING_STATE_MEANING`,
  `DENSITY_aesthetic_integrity`.

### Screenshot-led micro-refinements — second pass (2026-11-06, clone@69a0fcb)

A second review of the same committed RAILS captures, using the tree's own
vips stack for contact sheets and 1:1 crops (`scripts/analysis/make_sheets.py`,
`make_crops.py`, `make_crops2.py`; pyvips/libvips, matching the `Vips::Image`
usage in STUDIO/postpro and the `image_processing` Gemfiles). The first pass's
constraints still hold: reproduce each finding in the Chrome/CDP suite before
changing source; keep the product dialects, operator-owned palette/typefaces,
canonical tokens and original marks intact.

Suspicions refuted against source in this pass, recorded so they are not
re-raised: the Mr. Damascy strings are clean at 1:1 in
`mrdamascy/config/locales/nb.yml` ("Drikkegis til kureren?", "Sahtein-kortet",
"Kjøkkenbrettet", "Bekreftet", "Alt som skal grilles, i én rekke"); Amber's
second editorial nav item is "Antrekk" (`amber/config/locales/nb.yml:61`), not
a garbled label; Radio's "Utvalgt spor" is spelled correctly; the floating
bottom-right pill on brgen desktop is the existing chat affordance, not a
misplaced sign-in control. The aliased Amber wordmark in both captures is
motivation for amber-057 (§8.1), not a new row, and the Amber desktop tile
measure is already owned by the Bymorgen item above.

- [ ] **Stale-capture inventory.** Committed captures contradict current
  source in at least three rendered elements. The marketplace hero price
  prints blue and underlined, while source styles it `var(--bol-price)`
  (#c91f2c, tabular numerals) on a plain `strong`
  (`brgen/app/assets/stylesheets/_brgen_shared_overrides.scss:438,554` over
  `brgen/engines/marketplace/app/views/marketplace/listings/index.html.erb`). The
  messenger desktop "Meldinger" heading sits on a partial-width grey box,
  while source paints `.messenger-conversation-header` as a full-pane
  elevated bar (`brgen/app/assets/stylesheets/_brgen_messenger.scss:363`).
  The maps captures still show the raw kind value "place" at the page top,
  and the fix in `brgen/engines/maps/app/views/maps/places/_card.html.erb` covers the
  card partial only — verify the kind select and page header at recapture.
  Recapture every committed RAILS capture at one revision after the pending
  items close, and record the revision beside the image so capture age is
  readable from the file. Measure the marketplace utility strip ("Rask
  levering, også på kvelden" et al., `brgen/config/locales/nb.yml:86-88`)
  at 1:1 for size and AA contrast while there.
  Laws: `TRUTHFUL_STATUS`, `OPERATOR_RENDERED`, `PROPORTION_contrast`.
- [ ] **BIZ template defects.** BLOCKED (2026-11-06): the row itself makes
  the bob/bob2 retrofit the operator's decision (PRESERVE_FIRST); needs that
  decision. Original row: `BIZ/__templates/bob.html` and
  `bob2.html` both open with a spreadsheet-helper `<script>` block before
  `<!DOCTYPE html>` (standards-mode risk), and bob.html's print block has a
  malformed selector (`aref^="mailto:"]`). The pair also set
  `--width-content: 48rem` (≈96 characters at 16px, past the 75-character
  ceiling) against the BIZ contract's 66-character measure
  (`BIZ/README.md`, `BIZ/syre.html:42`), carry four font weights
  (400/500/600/700) against `BRINGHURST_scale`, use bare `:focus` instead of
  `:focus-visible`, and set negative letter-spacing on body text. The
  historical files stay untouched (`PRESERVE_FIRST`); `bob3.html` is the
  corrected correspondence template built from them. Retrofit the fixes
  into the bob/bob2 pair only as a new version on the operator's decision.
  Laws: `BRINGHURST_measure`, `BRINGHURST_scale`, `REACH_focus_visible`,
  `PRESERVE_FIRST`.

## 5. MASTER CLI, web, voice and face

- [ ] **CLI performance and interaction.** Measure boot, first token,
  completed-reply latency and memory on current main. Improve measured
  bottlenecks without blocking input on face rendering. Finish result-first
  output, live status, collapsed tool output, width-aware wrapping,
  NO_COLOR/dumb-terminal behavior, PTY cancellation and terminal restoration,
  paste/multiline handling, queued interruptions, actionable errors, real
  help examples, fast startup, session resume, /diff and JSON-only quiet mode.
- [ ] **Web control surface.** Make conversation, face, missions and live log
  useful together. Prove mission transitions, morning summary and explicit
  decisions, per-hunk diff review, before/after visual review, mobile and
  keyboard access, reduced motion and session search. Add health/spend views
  only when their backing measurements are reliable; hold no secrets.
- [ ] **Voice.** Measure time-to-first-audio. Improve sentence streaming,
  interruption on typing/speech, phrase caching, short spoken forms for code
  and paths, secret suppression, per-sentence Norwegian detection, loudness
  and local fallback. Report worker failure truthfully. Voice default/startup
  behavior remains an operator decision.
- [ ] **One face contract.** Keep the existing single FaceWorld/FaceState
  renderer, frame limits, caching and reduced-motion behavior. Finish
  phoneme-timed lip sync, Norwegian vowel shapes, listening pose, attention
  cues and CLI/web snapshot coverage without a second renderer.
  2026-11-11: unsupported explicit visual descriptors now leave the portrait
  intact; fallback lip sync maps æ/ø/å through the existing 45 ms audio-clock
  path. The generated loader's six source digests were checked. Listening and
  attention paths already have shared-policy implementations and focused tests.
  New Node regressions are authored but NOT_RUN; cross-renderer snapshots and
  real browser/device acceptance remain open.
- [ ] **Avatar geometry.** Derive deterministic particle positions from the
  recovered avatar reference inside the current renderer; preserve fallback
  and point budgets, then prove narrow/wide browser and GPU behavior.
- [ ] **Radio-to-face motion.** The existing stipple shader now applies a bounded,
  audio-energy inward warp from the shared `audio:update` bus; reduced-motion
  and still modes force it to zero. Track-driven transitions between the two
  current visualizers, rendered beat-response proof, and mobile/desktop playback
  remain open. Keep the existing transport bar.
- [ ] **Many-to-one face introduction.** Source landed: deterministic carriers now
  converge into the carved-field portrait in the existing stipple renderer;
  duration is token-owned and reduced motion resolves immediately. Rendered
  first/repeat-visit, boot-recovery and narrow/wide browser proof remains open.
  Do not copy the show's title treatment or community-governed mask motifs.
- [ ] **Conversation evaluation.** Replay representative prior conversations
  for answer-first behavior, no repeated known facts, one necessary question
  at most, natural interruption/resumption, preference use and uncertainty.
  Turn recurring corrections into regressions, not another personality system.

## 6. Ownership and documentation simplification

- [ ] **Semantic ownership census.** For each real duplication candidate,
  map owner, callers, constants/assets/views, autoload/eager-load behavior,
  routes, migrations, serialization/public APIs, tests, security/tenant/
  transaction contracts, destination and rollback. Classify MERGE, MOVE,
  RENAME, INLINE, DELETE, RETAIN or INVESTIGATE. Compare behavior, not
  hashes or names; never delete based only on file size, path depth or an
  unclear caller.
- [ ] **Documentation reduction.** Keep one canonical entry at each real
  boundary (repository, tree, product/engine). Remove stale instructions only
  after checking references, generators, links, tests and agent entrypoints.
  Preserve useful recovery/provenance records. Update sources and generators
  together; add no Markdown files.
- [ ] **BIZ document-family implementation.** The current source contract now
  defines distinct business-model/plan, funding, legal/contract, corporate and
  financial/analytical profiles. The production pipeline still publishes the
  existing business-plan family only; implement separate family validators,
  accessible templates and qualified review workflow before claiming legal or
  institutional deliverables complete. Inspect every page raster at print size;
  raster generation alone is not visual approval.
- [ ] **Historical hardening review.** Reconcile the remaining P01–P11
  findings in `MASTER/docs/history/fix-review-log.md`. L4 stale-member
  detection/tests, L5 heredoc/keyword detection plus structured Council
  ideation, L7 declarative/runtime parity assertion, and L8 parse-time
  check-registry refusal now have source coverage on `main`; their focused
  test runs remain NOT_RUN. L4's stored census is not re-baselined until a
  pinned Ruby 4.0.5 run has reported exact member drift. Continue with the
  genuinely open R3/R8–R13/R16–R17/H2–H8 findings. R11 now has
  regression coverage for the load-bearing rescue boundaries: Swallow.safe_call
  handles StandardError but propagates SystemExit, Interrupt and NoMemoryError;
  the CLI turn boundary reports child SyntaxError/NoMemoryError as infrastructure
  results and preserves process exits and operator interrupts. The Ruby/ERB
  compile-only probes now catch StandardError and ScriptError, not Exception,
  so signals and process-control failures remain visible. Five focused
  regressions are authored but NOT_RUN. The full source census of load-bearing
  rescue sites and review of each fallback's operational consequence remain open. The LLMDispatcher
  Replicate chat poll is source-fixed for URL trust, bearer-token confinement
  and network deadlines. MASTER's ReplicateClient reads private token files through a verified
  descriptor with a 256 KiB cap, fingerprints provider error bodies instead
  of exposing their text, applies equal jitter beneath the shared exponential
  retry ceiling, rejects dot/escaped/backslash API path segments, restricts
  pagination cursors to `/v1/models`, rejects redirects and caps download/API
  bytes under monotonic deadlines. Its API-path, cursor, download and response
  regressions are authored but NOT_RUN. STUDIO ReplicateClient validates
  model, version, training and prediction identifiers before URL interpolation
  and rejects dot-segment or escaped API paths. Its transport caps streamed API
  JSON responses at 16 MiB, caps uploads/downloads at 4 GiB, refuses symlink and
  non-regular download targets, canonicalizes the output parent, clamps socket
  timeouts to a monotonic total transfer deadline, preserves existing downloads
  on partial failure, and uses monotonic prediction/training deadlines. The
  additional transfer/deadline regressions are source additions, not executed
  proof. Live provider/upload integration remains open. The later source pass also closes the direct STUDIO training
  bypass: `ReplicateClient#train_lora`, `upload_file` and `upload_zip` now
  require `subject:` and check the shared consent record before provider
  schema lookup, model creation, file upload or training. Tests prove the
  direct training/image/ZIP paths refuse before provider requests; authored,
  NOT_RUN. H2/H3 now have source
  coverage: tool hooks default to deny on faults, MCP SSE is loopback-only and
  enabled package versions are pinned (the git server remains disabled). H7's
  local web startup refuses unknown port listeners; Dilla player shutdown
  signals/reaps only its owned direct child; TTS workers remain waitable direct
  children and retirement refuses command-line sweeps or unowned socket paths.
  The local MLX TTS server also retains its detached waiter, avoids duplicate
  starts while that child lives, and retries after the owned child exits; the
  real-child restart regression is authored but NOT_RUN. The CDP runner now
  gives Chrome an isolated process group, TERM/KILLs that group with bounded
  waits, confirms the leader was reaped and the group gone, and preserves the
  profile when shutdown is inconclusive. Its real-spawn/renderer regression is
  authored but NOT_RUN. WebDriver now starts its direct driver child in an
  isolated process group, confirms direct-child reap and renderer-group exit,
  and retains PID/session state when shutdown is unconfirmed; actual spawn and
  renderer regressions are authored but NOT_RUN. Triangle down and /fix server
  leases now use bounded TERM/KILL group shutdown; PID/owner records are kept
  until process-group exit and exact lease identity are confirmed. The no-PID
  fallback requires an app-owned listener that is its own process-group leader.
  Real-group, retry, replacement-lease and refusal regressions are authored but
  NOT_RUN. Triangle's sibling-worktree reaper is source-fixed: it refuses
  non-sibling paths and non-leader listeners, then uses the bounded shared
  process-group stop; live-group and non-leader refusal regressions are authored
  but NOT_RUN. Dependency-manager boot capture now applies bounded TERM/KILL
  and verifies the whole child process group has disappeared; when it cannot
  prove exit it reports termination UNCONFIRMED. Descendant-held-pipe and
  unconfirmed-stop regressions are authored but NOT_RUN. The broader
  process-kill census and provider-boundary audits remain open. The constitutional scan runner now
  puts its child in an isolated process group and applies one monotonic deadline
  to both process exit and output-pipe EOF; timeout escalates TERM to KILL and
  checks group disappearance. A regression covers an exited leader with a
  descendant holding the pipe open; authored but NOT_RUN. The source-
  evidence runner now applies its deadline to child exit and both output pipes,
  refuses unsafe numeric-PID fallback on process-group ESRCH/EPERM, and reports
  whether group termination was actually confirmed. A descendant-held-pipe
  regression and signal-boundary tests are authored but NOT_RUN. Photo
  post-processing likewise covers the child and inherited output pipe under
  one deadline, with bounded group termination and a real descendant regression
  (NOT_RUN). The check ladder now delegates to the sanctioned
  Master::Io::Exec.capture2e rather than maintaining an unbounded reader join;
  its source contract and inherited-pipe executor regression are authored but
  NOT_RUN. MASTER's Replicate API URL validator also rejects dot, escaped and
  backslash path segments before attaching its bearer token. Focused
  regressions are authored/extended but NOT_RUN.
  H6 is partial: `.zshrc` checks operator-file ownership and group/other mode
  bits; `PermissionAudit` checks `/etc/<app>.env` as `root:<app>`, storage owner
  as `<app>`, daemon-log owner and symlinks in every protected path component.
  `health_check.rb` uses `lstat` and includes `/etc/rails/*.env`; wrong-owner,
  wrong-group, leaf- and parent-symlink regressions are authored but NOT_RUN.
  The operator.env source-path test and live vm23 permission run remain open. R8 DesignRun candidates now use the existing Transaction journal, check exact source and candidate hashes across measurement and retention, and receive a second render/judge immediately before delivery. Interrupted open candidates recover on the next design run and rebuild affected app CSS; recovery fails closed when a restored Rails source has no available CSS builder. Definite refusals roll back; ambiguous deliveries retain their manifest for recovery. Focused regressions are authored but NOT_RUN. Full-run/post-commit verification rollback and isolation from non-transactional readers remain open.
- [ ] **Local Claude hooks.** On macOS, launch a real Claude Code session and
  verify project hooks load through the `.claude` symlink.
- [ ] **AI3 recovery.** Compare recovery manifests with recoverable historical
  Git/archive objects; map unique behavior to current owners and state what
  is actually absent. Do not restore a former tree wholesale.
- [ ] **Account-wide transcript coverage.** Resume the earlier archive review
  only when an official ChatGPT export is supplied. Preserve source IDs and
  timestamps, deduplicate handoffs and do not claim all conversations were
  audited without that source.

## 7. OpenBSD production safety and external seams

- [ ] **Measure vm23 before changing it.** The 2026-11-04 note reported 1 GB
  and near-exhausted swap; that is not a current measurement. Capture live
  RAM, swap, service RSS, job processes and health first. Present a provider
  upgrade only if current measurements justify it. Do not add swap, restart
  services or change production as an unapproved stopgap.
- [ ] **Reproducible deployment artifact.** Build code, assets and
  OpenBSD/amd64 native gems on the Mac. vm23 should unpack and run a reviewed
  artifact, not compile dependencies during deployment. Prove manifest,
  checksums and target compatibility.
- [ ] **Staged deploy and rollback.** Prove isolated release directory,
  atomic live switch, pre-deploy rehearsal, resource guard, route-manifest
  smoke test and rollback to the previous known-good release. Preserve
  actual host and backup/restore evidence.
- [ ] Run native `pfctl -nf /etc/pf.conf` on OpenBSD; source parsing on macOS
  is not equivalent.

External/operator evidence remains separate from code work: individual
distribution rights for the 35 Radio Bergen recordings; human usability and
screen-reader sessions; the macOS Claude hook launch; live vm23 capacity
decision; distance, expiring-post and voice-default decisions. Review account
quota after 2026-12-01 before considering Ollama re-enablement. Do not
re-enable it by assumption.

## Deferred, not active work

- pub5 source work is active on `main`; release acceptance remains deferred
  until the operator-only evidence is complete and recorded.
- The archived movie-acquisition proposal is not approved. Reopen only for a
  lawful provider/catalogue integration with explicit provenance and licensing.
- Amber 3D garment inspection and new STUDIO audio-reactive artwork remain
  experiments until real assets, a concrete consumer and measurable acceptance
  exist. Preserve the non-WebGL path and single audio clock.
- Perplexity's old task is retired: its generic hosted-provider route has been
  removed from `models.yml` and a regression asserts it is not routable.
  Reopen only for a provider-specific adapter with reviewed product choice,
  citation/usage preservation and bounded canary.
- Replicate ownership is settled: STUDIO owns `STUDIO/replicate/client.rb`.
  Do not reopen the ownership question or move its implementation into MASTER.

---

The previous list mixed completed source changes, duplicated verification,
historical narration and unapproved alternatives. This version retains
unresolved outcomes and removes the false impression that every checkbox is
a separate current task.

## 8. Consolidated backlog inventory

This section brings the repository's remaining tracked TODOs, backlog rows, UX acceptance work, workstream wishlist and operator-only dependencies into the single root register. It is an index as well as an action list: the structured source files remain the detailed evidence and decision records, not competing Markdown queues. Do not treat an aspirational or unpicked idea as implementation authority.

The tracked repository has one TODO file: this root `TODO.md`. The cross-tree contract in `MASTER/test/test_single_backlog_contract.rb` intentionally rejects nested TODO files. Keep that contract. Do not delete the YAML ledgers below; their IDs, states, rejected alternatives and evidence contracts are consumed by MASTER and are not duplicate prose backlogs.

### 8.1 RAILS refinement survey — two items still open

`RAILS/refinements.yml` was compacted on 2026-11-12 to the 2 unresolved rows only. The preceding snapshot contained 777 rows (763 done, 12 invalid, 2 open); completed and disproved dispositions remain recoverable in Git history and are not copied into the active ledger. The 2 open rows still require their stated rendered evidence. 2026-11-07 session, sandboxed (no Ruby 4.0.5, no Chrome/CDP suite): every Ruby suite run is NOT_RUN; the app bundles compile with dart-sass and the rendered claims below carry their own harness. Second pass the same day: the sandbox gained a Debian Ruby 3.3.8, and with `PUB5_RUBY` (the runner's own override in `OPENBSD/mirror/lib/ruby_runner.rb`) the source-reading contract suites run for real — design contract 15 runs / 149 assertions, the link-embed privacy contract 5 / 40, the SVG wordmark 2 / 5, all green; only what needs a Rails bundle (rendered pages, migrations) stays NOT_RUN here. 2026-11-08: Ruby 4.0.5 itself now builds in the sandbox (source build, libyaml into `~/.local/ruby-deps`, psych verified), so the same source-reading suites ran on the pinned interpreter without the `PUB5_RUBY` override — design contract 15 / 149, link-embed privacy 5 / 38 (the rebased tree's shape), visual identity (the wordmark's home) 12 / 136, all green; `amber/test/logo_contract_test.rb` still needs the app bundle (its `test_helper` boots the environment) and stays NOT_RUN here. Row evidence still waits on those rendered runs.

- [ ] **shared-010 — Button sizing.** Source landed 2026-11-07: `_buttons.scss` carries `$compact-contexts` only and the class survives behind a default-off `$legacy-small` opt-in; the shared comment/notification/newsletter/artifact partials, four JS-created buttons, amber's flash undo and 32 tree-wide-verified brgen-family sites name no size (each context held only compact buttons at a full-ERB sweep). The mixed containers (rsvp-bar, push-prompt, messenger-details-section, order-actions, the form-wrap--flush forms, the generic `.cluster`/`.page-header`/`.field` primitives, the no-class rows, `_live_search_form` and `_master_invite`) keep the class pending per-site rendered checks; a ratchet in `design_contract_test.rb` pins the naming file count at 75 and only down. Row stays open for that rendered evidence.
- [ ] **shared-029 — Privacy-preserving embeds.** Source landed 2026-11-07: the thumbnail is fetched once where the oEmbed answer arrives (the link-embed job, the compose preview), written to `storage/link_embeds/thumbnails` content-addressed by the SHA-256 of the provider URL, and served from the app's own `/link_embeds/thumbnails/:digest` endpoint; the partial renders no provider URL and a page view contacts no provider. `link_embed_privacy_contract_test.rb` pins the shape and the render test asserts no provider image host in the page; the contract suite now runs green on the forced sandbox Ruby, the rendered run still does not. Row stays open for rendered evidence.

Close these rows in `RAILS/refinements.yml` only with the corresponding source and rendered evidence. Do not copy the 763 completed or 12 invalid rows back into the active list.

### 8.2 MASTER UX acceptance matrix — 90 unverified contracts

`MASTER/data/law/ux_refinements.yml` contains 90 unique acceptance targets (`UX001`–`UX090`); all 90 remain `acceptance_required` and none is `verified`. Work through the existing proof contract and record receipts there. A source change or a screenshot alone does not satisfy a row whose contract also requires unit, terminal, browser, visual or accessibility proof.

- [ ] **Input UX001–UX015:** Immediate acknowledgement; preserve an unsent draft; intentional multiline entry; bracketed-paste safety; stable input while streaming; duplicate-submit prevention; command-history navigation; searchable history; filesystem path completion; command completion; visible interaction mode; empty-input guard; Unicode editing safety; explicit end-of-input behaviour; recovery after command exception.
- [ ] **Terminal UX016–UX030:** Active target indicator; model/provider indicator; idle versus waiting distinction; truthful busy state; cancellation affordance; degraded-capability state; stable visual baseline; bounded status text; narrow-terminal layout; face never intercepts prompt authority; monochrome operability; no decorative banners; repository-context visibility; canonical prompt vocabulary; REPL versus system-shell distinction.
- [ ] **Diagnostics UX031–UX045:** Outcome-first diagnostics; standard status verbs; elapsed-time reporting; actionable failure recovery; FAILED versus INCONCLUSIVE; no duplicate summaries; stable event prefixes; output navigation; precise failure location; bounded diagnostic traces; meaningful exit codes; predictable piped output; secret redaction; run identifiers; intentional quiet mode.
- [ ] **Command help UX046–UX060:** Registry-generated completions; canonical command spellings; helpful unknown-command suggestions; explicit read/write boundary; target preview before mutation; normalized flags; dry-run semantics; clear usage errors; argument completion; copyable paths; machine-readable output schema; stdout/stderr ownership; useful command listing; risk-aware confirmation; conservative natural-language routing.
- [ ] **Browser recovery UX061–UX075:** Scroll follows only near bottom; draft survives disconnect; reconnect does not duplicate turns; explicit stream terminal state; mobile keyboard and safe area; honest stop semantics; visible keyboard focus; accessible icon labels; status without colour; reduced-motion behaviour; forced-colours behaviour; 320px reflow; preserve conversation text shape; usable touch targets; recoverable browser errors.
- [ ] **Visual accessibility UX076–UX090:** Consistent prompt baseline; predictable heading wrapping; long-identifier handling; tabular numerals; muted-text contrast; unclipped focus ring; remove repeated metadata; clear primary-action hierarchy; useful empty states; aligned field labels; contextual validation errors; stable loading layout; bounded animation duration; screenshot-comparison evidence; text zoom and font scaling.

The row-level owner trees, proof types and receipt requirements remain in `MASTER/data/law/ux_refinements.yml`; the contract is tested by `MASTER/test/test_ux_refinements_contract.rb`.

### 8.3 Product and platform gaps — preserve every unresolved ledger row

`MASTER/data/gaps.yml` has 54 rows: 9 picked, 35 open, 4 blocked and 6 satisfied. The satisfied Dating row is intentionally not repeated as work; completed root-index entries stay checked with source evidence. A picked row needs its named convergence workstream completed and evidenced. An open row is a decision candidate, not permission to build. A blocked row stays blocked until its stated prerequisite exists. Every implementation remains subject to MASTER's laws and normal /fix gates.

**Brgen**
- [ ] `brgen_ai_feed_ranking` — PARTIAL 2026-11-11: deterministic recency-plus-local-engagement ranking is implemented in `RAILS/brgen/app/models/post.rb`; `RAILS/test/feed_ranking_contract_test.rb` covers the contract. Run focused and app suites on the installed compatible Ruby; NOT_RUN here.
- [ ] `brgen_cold_start_feed` — open; consider a labelled follows-plus-city-popular feed so a new reader can see a living city.
- [ ] `brgen_creator_monetization` — open; depends on the one shared commerce domain.
- [ ] `brgen_activitypub_inbound` — open; remote media proxying, per-origin controls, blocklist and moderation must precede storage.
- [ ] `brgen_recurring_events` — open; decide whether a small recurrence materialiser is warranted; external ticket links remain a valid simpler boundary.
- [ ] `brgen_city_population_seeds` — open; use a checked-in public-data table for the 43 registry cities if the value is demonstrated.

**Messenger**
- [ ] `messenger_webrtc_calls` — blocked; requires an operator-approved STUN/TURN service and host capacity.
- [ ] `messenger_notify_suppression` — open; decide how the active conversation suppresses redundant unread notifications without stale-tab claims.
- [ ] `messenger_business_crm` — open; consider a business inbox, labels and canned replies, with money features kept on the shared commerce domain.

**Marketplace**
- [ ] `marketplace_ai_recs` — open; prefer explainable co-view or category/price-band recommendations over a model without useful data.
- [ ] `marketplace_coupons` — open; one transparent campaign/credit ledger, not a second checkout accounting path.
- [ ] `marketplace_contact_relay` — blocked; requires inbound mail routing and expiring per-listing addresses on vm23.
- [ ] `marketplace_liquidity` — open; measure empty categories, saved-search demand and unmet supply before advertising.
- [ ] `marketplace_paid_boosts` — open; preserve quality-weighted organic discovery, clear sponsored labels and caps; payment never buys a trust outcome.
- [ ] `marketplace_seller_analytics` — open; derive seller/listing analytics from existing events where possible.

**Dating, Playlist and Takeaway**
- [ ] `dating_premium_boost` — open; any premium, boost or super-like design must preserve consent, avoid dark patterns and never sell moderation or safety outcomes.
- [ ] `playlist_creator_donations` — open; creator tips may use the shared commerce domain; do not sell an ad-free tier while there are no ads.
- [ ] `referral_reward_consumption` — open; define the real, member-visible benefits behind `playlist_pro` and `dating_pro`, then wire their gates. Referral credits currently record entitlement only; do not market them as usable Pro access until those features exist.
- [ ] `takeaway_pro_surface` — open; promotion, loyalty and coupons depend on shared commerce and liquidity foundations.

**TV, Maps and shared commerce**
- [ ] `tv_live_stream_infra` — blocked; requires an explicitly chosen media server and delivery/transcoding tier; the existing broadcast state machine is not proof of live streaming.
- [ ] `maps_poi_substrate` — open; decide whether Places should become the stable shared POI service consumed by verticals.
- [ ] `commerce_shared_domain` — open; design one shared Commerce/Ledger/Campaign/Entitlements domain for all verticals, not separate billing stacks.
- [ ] `commerce_private_seller_verification` — open; determine a defensible, explainable proof for a private seller without an organisation number.
- [ ] `commerce_local_ads` — open; only after liquidity is measured and the shared campaign/ledger domain exists.
- [ ] `brgen_art_ad_banner` — open; build the named minimal art-directed banner only with approved sponsored copy, image rights and destination. Keep ads labelled, and keep AdSense gated until a certified consent platform is in place.

**Amber**
- [ ] `amber_fashion_embeddings` — open; start with owner-tagged typed attributes, not a Postgres/pgvector migration for a personal wardrobe.
- [ ] `amber_visual_similarity` — PARTIAL 2026-11-11: typed-token cosine matching is implemented in `RAILS/amber/app/services/wears_well_with.rb`; service and contract tests exist. Run focused and app suites on the installed compatible Ruby; NOT_RUN here.
- [ ] `amber_fitting_room` — open; keep garment-on-silhouette representation honest; do not imply body measurements or fit guarantees.
- [ ] `amber_mood_matcher` — open; use reader-declared tags or a colour-first alternative; never infer a reader's mood.
- [ ] `amber_event_outfit_planner` — open; consider outfits against an event the reader selects, with soft formality/season/recent-wear constraints.
- [ ] `amber_sustainable_resale` — open; release an item into the existing Marketplace rather than building a second resale surface.
- [ ] `amber_weather_suggestions` — blocked; no weather source is currently part of the suite; do not fabricate conditions.
- [ ] `amber_outfit_whole_score` — open; decide between explainable arithmetic and showing the combination without a score.
- [ ] `amber_trends_designers` — open; prefer dated, curated local-designer content over scraped global trend feeds.
- [ ] `amber_style_agents` — open; any MASTER integration must be advisory, read-only and attributed.

**BSDPorts**
- [ ] `bsdports_multi_parsers` — open; keep OpenBSD as production scope; other ports trees remain opt-in/on-demand and require an explicit need.
- [ ] `bsdports_semantic_search` — open; evaluate SQLite FTS synonyms first; a local corpus/similarity pass must justify its cost.
- [ ] `bsdports_knowledge_graph` — open; expose useful dependency and reverse-dependency questions from existing parsed data, not a new infrastructure graph.
- [ ] `bsdports_package_intel` — open; consider factual freshness/maintainer signals and a vulnerability source with reliable provenance.
- [ ] `bsdports_cli_sponsorship` — open; add optional pay-what-you-want support handoff only after a verified recipient and sponsor/payment URL exist; package search and CLI use remain free and unblocked.

**MASTER and STUDIO**
- [ ] `master_fleet_health` — PARTIAL 2026-11-10: `FleetPanel`, dashboard wiring and injected-probe contract landed; unit suite and live vm23 health/render proof remain NOT_RUN.
- [ ] `master_dead_payload_facts` — PARTIAL 2026-11-10: provider quota, per-model forecasts and cache-measurement state now render; quota/dashboard suites and browser verification remain NOT_RUN.
- [ ] `master_pair_admin_surface` — open; add an authenticated operator surface for pairing issue/list/destroy only if its permission boundary is proven.
- [ ] `master_face_soothing` — picked; complete `master_face_breath` without adding colours or exceeding visual budgets.
- [ ] `master_voice_dsp_lanes` — picked; complete `master_voice_browser_dsp` so browser and terminal build the same declared voice presets, with honest unsupported-node behaviour.
- [ ] `master_voice_cooler` — picked; complete `master_voice_cooler_default` only after listening acceptance; operator taste remains the final gate.
- [ ] `dilla_corpus_depth` — sample credits, measured timing, 3/5/7-bar form and Bach/Satie lineage now surface in `Voice::Dilla.brief`; exact Donuts chord transcription remains listening-dependent (the empty arrays are deliberate, not guessed). Regression added; NOT_RUN on the installed compatible Ruby.
- [ ] `free_model_lanes` — picked; complete `free_compute_design_of_record` with dated quota/source checks and explicit gates; do not wire provider lanes merely because a free tier is listed.

The complete candidate records and rejected alternatives live in `MASTER/data/ideations/*.yml`. Their `keep` verdict means a candidate survived adversarial critique; it is not blanket approval to implement. The 14 records are: `amber.yml`, `brgen.yml`, `bsdports.yml`, `creativity_lab.yml`, `dating.yml`, `maps.yml`, `marketplace.yml`, `master_surface_audit.yml`, `master_web_dilla_free.yml`, `master_web_face_voice.yml`, `messenger.yml`, `playlist.yml`, `takeaway.yml` and `tv.yml`. Consult the individual candidate and critique before selecting a direction. The Dating gap `dating_two_sided_ranked_for` is already marked satisfied in the gap ledger and is not open work.

### 8.4 MASTER convergence wishlist — 36 unfinished workstreams

`MASTER/convergence.yml` is the non-authoritative assistant wishlist and implementation/evidence map. It currently records 21 landed, 21 partial, 7 evidence-dependent and 8 missing workstreams (36 unresolved; 57 total). These IDs are proof/ownership cross-links to the sections above, not permission to create duplicate implementations. Close each only when its named implementation and proof are real.

**Evidence-dependent — 7**
- [ ] `voice_local_first` — local-first speech ladder and real microphone proof.
- [ ] `face_semantic_motion` — large 3D face semantic motion in a real browser and on a device.
- [ ] `rails_product_completion` — production marketplace, authentication and media flows with staging credentials.
- [ ] `openbsd_appliance` — vm23 deployment, restore, DNS, TLS and resource proof.
- [ ] `dilla_music` — musical quality, authenticity and listening decisions.
- [ ] `recovery` — off-host backup and clean-host restore drill.
- [ ] `personal_companion` — resident voice-first phone companion on real Termux hardware.

**Partial — 27**
- [ ] `studio_provenance` — media provenance through every generation stage.
- [ ] `security_capability_graph` — capability ownership and least-privilege graph.
- [ ] `event_replay` — canonical event vocabulary, provenance and replay.
- [ ] `task_scoped_prediction` — separate event-prediction streams across correlated tasks.
- [ ] `prediction_evaluation` — walk-forward comparison of contextual prediction against shared-stream and baseline models.
- [ ] `self_model_calibration` — measure capability outcomes and confidence calibration from explicit evidence.
- [ ] `cognition_measurement` — report workspace activity and saved-state restoration without consciousness claims.
- [ ] `task_outcome_learning` — per-target /fix outcome prediction from hashed receipts, scored before learning.
- [ ] `cognition_learning_benchmark` — prequential learning benchmark with no-learning ablation and constant baseline.
- [ ] `browser_proof` — rendered geometry, accessibility and performance evidence.
- [ ] `search_quality` — search relevance, explanations and a quality corpus.
- [ ] `moderation_governance` — moderation evidence, appeals and audit.
- [ ] `installation` — one-command host-aware installation and truthful doctor output.
- [ ] `structural_craft` — measured architectural collapse/relocation with proof.
- [ ] `unified_command_language` — one semantic command surface across CLI, web, voice and device.
- [ ] `media_effects` — Ruby-native analogue audio and image processing.
- [ ] `master_face_breath` — stipple field breathes in brightness only and freezes under reduced motion.
- [ ] `master_voice_browser_dsp` — browser builds declared character presets in parity with terminal.
- [ ] `master_voice_cooler_default` — default voice room/doubler and optional presets; listening acceptance required.
- [ ] `dilla_corpus_measures` — sourced Dilla timing observations recorded without silently tuning generation.
- [ ] `free_compute_design_of_record` — dated free-compute landscape and verified quota assumptions.

**Missing — 8**
- [ ] `brgen_feed_ranking_deterministic` — PARTIAL: source and `RAILS/test/feed_ranking_contract_test.rb` exist; installed-Ruby test and full feed verification remain NOT_RUN.
- [ ] `amber_similarity_right_sized` — PARTIAL: source and `RAILS/amber/test/services/wears_well_with_test.rb` plus the bare-Ruby contract exist; installed-Ruby tests remain NOT_RUN.
- [ ] `master_fleet_panel` — PARTIAL 2026-11-11: `FleetPanel`, dashboard wiring and `MASTER/test/test_dashboard_fleet_panel.rb` exist; unit execution and live vm23 health/render proof remain NOT_RUN.
- [ ] `master_quota_facts` — PARTIAL 2026-11-11: quota/cache payload rendering and dashboard contract coverage exist in `MASTER/test/test_dashboard_fleet_panel.rb`; quota suite execution and rendered-browser proof remain NOT_RUN.
- [ ] `inconclusive_aging` — PARTIAL 2026-11-11: receipt ageing/reopening logic and `MASTER/test/test_convergence_proof.rb` cases exist; run focused proof suite on the installed Ruby and inspect a real receipt, NOT_RUN here.
- [ ] `constitution_self_budget` — PARTIAL 2026-11-11: `MASTER/checks/data/constitutional_budget.yml` carries the 6,717-line ceiling and `MASTER/test/test_constitutional_budget.rb` pins fit + down-only ratchet; run the tests on the installed compatible Ruby, NOT_RUN here.
- [ ] `documentation_completeness` — public-contract changes carry documentation-review proof in the same task/commit.
- [ ] `ops_alert_channel` — heartbeat failures reach one operator-owned relay with an allowlisted endpoint and secret held outside the tree.

### 8.5 Operator-only and external evidence seams — 55 dependencies

These items require a real person, host console, device, registrar, provider credential, rights decision, material or listening judgement. They are included here so the root register exposes the full outstanding surface; the required evidence remains specified in `MASTER/data/operator_seams.yml`. Do not pretend to complete them from source inspection or simulation.

- [ ] **MASTER (17):** `android_consent_ux` (device); `android_termux_install` (device); `selfie_route_live` (provider); `browser_vision_end_to_end` (browser); `face_in_a_real_browser` (browser); `voice_by_ear` (ears); `worktree_delivery_against_github` (credential); `release_acceptance_on_an_idle_host` (idle host); `external_assessment_on_authorised_targets` (credential); `nmap_licence_boundary` (rights); `assessment_business_hypothesis` (material); `remote_branch_aliases` (credential); `assistant_calendar_or_mail_live` (credential); `messaging_channel_choice` (rights); `session_browser_post_policy` (rights); `advice_quality_human_review` (ears); `deepseek_findings_export` (material).
- [ ] **OPENBSD (15):** `shell_init_credential_rotation` (credential); `unregistered_domains` (registrar); `watched_all_target_deploy` (console); `deploy_failure_trap_window` (console); `second_offhost_backup_and_key_recovery` (console); `dnssec_ds_at_registrars` (registrar); `monitoring_and_crontab_on_vm23` (console); `two_consecutive_deploys` (console); `syspatch_in_a_console_window` (console); `full_check_after_deploy` (console); `privilege_migration_on_vm23` (console); `manual_pages_on_openbsd` (console); `prompt_parity_on_a_live_openbsd_shell` (console); `openbsd_native_suite` (console); `csp_enforced_on_vm23` (console).
- [ ] **RAILS (16):** `brgen_first_screen_in_chrome` (browser); `tenant_isolation_live` (browser); `messenger_journey_in_a_browser` (browser); `payments_in_provider_staging` (provider); `pwa_on_real_devices` (device); `city_registry_matches_dns_and_tls` (registrar); `journeys_in_all_three_apps` (browser); `amber_dashboard_geometry` (browser); `visual_identity_acceptance` (browser); `radio_whyp_tracks_imported` (console); `paid_plans_live` (credential); `checkout_steps_design` (material); `search_focus_shadow` (rights); `oauth_callbacks_live` (credential); `amber_outfits_on_the_real_catalogue` (material); `bsdports_lifecycle_on_openbsd` (console).
- [ ] **STUDIO (7):** `lora_source_refresh_and_paid_training` (provider); `private_media_and_history` (rights); `person_renders_and_duet_video` (material); `dilla_by_ear` (ears); `reference_workflow_with_a_real_link` (ears); `lora_route_end_to_end` (provider); `paid_media_cost_proof` (provider). The named `wenche` subject plan is §8.10, gated on written consent.

### 8.6 Aspirational horizons — visible, but not active by default

`RAILS/apps.horizon.yml` explicitly sets `agent_policy: ignore`. Its 47 planned rows are product horizons, not an unattended implementation queue. The gap IDs in §8.3 are the recorded candidate path; promote an additional horizon only after an explicit product decision, adversarial review, a named workstream and normal law-gated proof.

The broader horizons that need to remain visible are:

- [ ] **Messenger replacement threshold:** E2EE, delivered/read receipts, multi-device sessions and voice/video calls before claiming it can replace the operator circle's current messenger.
- [ ] **Takeaway consolidation:** decide whether food becomes a Marketplace vertical on the shared commerce rail; no parallel payment stack or migration without an explicit decision and rollback plan.
- [ ] **Marketplace catalogue scale:** shipping rates and labels, multi-currency, dispute/chargeback handling, catalogue-scale search and independently scalable heavy surfaces; bring the shelf, product page, buy box and checkout to one coherent standard.
- [ ] **Playlist creator surface:** creator uploads, reposts, waveform comments and discography-like profiles to support the SoundCloud/Whyp positioning; preserve import provenance and rights boundaries.
- [ ] **Shared commerce completion:** one ledger/campaign/entitlement source, seller credits, payment abstraction (refunds, invoices, VAT, reconciliation) and a revenue dashboard beyond the existing first slices; respect the liquidity-before-ads order.
- [ ] **Solidus/Dintero evaluation:** the planned Solidus core mount, starter storefront, native marketplace features, Dintero split checkout and Amazon feature-parity map remain staging/evaluation work. Do not replace native Marketplace flows or enable live checkout before provider staging, migrations, cutover and rollback are proved.
- [ ] **Amber media capabilities:** real garment matting/segmentation and richer try-on capabilities remain separate from the right-sized typed-attribute work; require real assets and a measurable consumer.
- [ ] **BSDPorts expansion:** FreeBSD/NetBSD parsers, semantic search and knowledge-graph ambitions remain subordinate to the OpenBSD-only production scope and a demonstrated reader need.
- [ ] **Own-domain horizon:** any planned domain/host work needs an actual zone, registrar decision, ACME configuration and host proof.

The authoritative feature/status detail is in `RAILS/apps.yml` and `RAILS/apps.horizon.yml`. Their planned rows are intentionally not to be confused with active implementation work.

### 8.7 Creativity experiments, decisions and refutations

`MASTER/data/ideations/creativity_lab.yml` records six experiments as implemented: `spark_cli`, `deploy_story`, `cities`, `domain_ghosts`, `tree_weight` and `law_weight`. Three remain deferred, not active: `city_pack_api` (no consumer/auth design), `semantic_canary` (no offline rubric/model budget) and `dilla_fixture_wav` (needs its STUDIO golden-hash pass).

`MASTER/data/proposals.yml` is the refutation ledger: 13 proposals landed, 18 refuted, none open. Preserve the rejected records and their reasons; do not re-propose them as fresh work without new evidence.

### 8.8 Runtime-generated wishlist — not present in the GitHub tree

MASTER's `Fix::Wishlist` reads/writes the local runtime ledger `.master/fix_wishlist.json`. That ignored runtime file is not present in the tracked GitHub tree, so its current suggestions could not be inspected or merged from GitHub.

- [ ] Export and review `MASTER/.master/fix_wishlist.json` from the live MASTER checkout; reconcile its still-valid entries against this root register and the convergence/gap IDs before claiming runtime-generated wishes are included.

### 8.9 Separate proposals that are not repository-wide backlogs

`BIZ/tools/fetat_proposal.md` is a substantive policy/project proposal, not a software task queue. Keep its research, legal questions and implementation blueprint in that document; only promote a specific, authorised and scoped software task into this register. Do not explode the proposal into speculative checkboxes.

### 8.10 `wenche` subject — gated on written consent

BLOCKED (2026-11-07): the intended source is the ME2 face archive from pub4 commit `8e1955ae` plus photographs at `tommervik.com`. Neither may be downloaded, prepared or trained until the subject's written consent and the photographer's licence exist as local records. Nothing below runs before step 1; the repository rule is that a public URL is not a rights grant. The shared `STUDIO/lora/consent.rb` gate now requires a separate written subject-consent document plus per-source rights evidence, and checks the exact subject, permission scope, private `evidence/` paths and owner-only permissions before Merethe recovery/preparation and likeness generation. It does not create or infer consent. The consent and integration regressions are authored but NOT_RUN on the pinned Ruby; this subject remains blocked until the real consent and photographer-rights records exist locally.

Ordered, and each step is gated by the one before it:

- [ ] **Consent record.** Create `STUDIO/lora/wenche/consent.yml` from `STUDIO/photograph/consent.example.yml` with `subject: wenche`, `likeness_generation: true`, `provider_processing: true`, and `source_rights` naming the evidence for each source set. Mode 0600, never tracked. The template is in the tree; `STUDIO/lora/*/consent.yml` is gitignored.
- [ ] **Source inventory and rights.** List every intended image with its provenance — ME2 frames and any website photographs separately — and record the photographer's permission or licence for training and provider processing. Exclude frames already judged unsuitable (overlays, obscured or cropped faces, intimate framing); the ME2 curation kept four of fifteen for identity use.
- [ ] **Dataset adequacy.** Reach the 12–18 image band with rights-cleared, face-led adult photographs before preparing a training ZIP. Four archived portraits are a starting subset, not a dataset.
- [ ] **Subject scaffold.** Add `wenche/subject.env` (trigger, descriptor, model) and a preparation script following the Merethe pattern: digest-verified recovery, caption set and the shared consent gate's required per-source evidence. No subject data or provider processing before a valid record exists.
- [ ] **Train.** Separate explicit paid-training decision on Replicate via `ostris/flux-dev-lora-trainer`; record job IDs, versions, costs and weights in the private subject directory. This is `lora_source_refresh_and_paid_training` (provider) in §8.5.
- [ ] **Render, grade, review.** `ruby STUDIO/photograph.rb --selfie-series --subject wenche` for stills through postpro. The subject reviews and accepts the likeness; a completed series is not an approval.
- [ ] **Promo.** Only after likeness acceptance: assemble the promo with `STUDIO/dilla/dilla.rb` as the music bed and postpro heavy passes for the grade, outside the checkout under the `output_paths.rb` contract. Publish only with a recorded publication decision.

---

**Consolidation rule:** Root `TODO.md` is the only cross-tree Markdown action list. `RAILS/refinements.yml`, `MASTER/data/law/ux_refinements.yml`, `MASTER/data/gaps.yml`, `MASTER/convergence.yml`, `MASTER/data/operator_seams.yml`, `MASTER/data/proposals.yml`, the ideation sheets and the RAILS feature inventories remain structured owners for IDs, proof receipts, provenance, accepted/rejected reasoning and state. Update the owner and this root index together when an item is implemented or its state changes. Do not create another backlog file.


### 8.11 Sandbox contract run — forced Ruby, 2026-11-07 (second session)

The full `RAILS/test` suite was run on the sandbox's Debian Ruby 3.3.8 against
the repo's own force hatch (`PUB5_RUBY`, `OPENBSD/mirror/lib/ruby_runner.rb`), with
`zeitwerk`/`activesupport` installed for the three deploy suites and zsh
extracted for the deploy-identity sourcing. Ledger: 161 of 163 suites pass,
0 NOT_RUN. The runs found and the same pass fixed the stale route-manifest
digests and an anchored-constraint pin, the AppsYmlValidator master
deploy_root, the billing-plans schema read, a missing-build fixture outside
the scanner's glob, a pre-rbenv runner pin, an under-stubbed Stimulus player,
two animations on the ease-out literal (one without its reduced-motion
guard) and three banked child-margin budgets; completed checklist rows are
deleted from this index, with the findings ledger and its fixes living in
git history.

Open, itemized, and not to be waved through — the split debt the ratchets
count. Both ratchets' law is "split it and lower the number; never raise":

- [ ] `file_length_ratchet_test.rb`: fifteen files sit past their ceilings or
  the per-kind limit with no row — brgen `_brgen_shared_overrides.scss`
  (2,264 code lines) and `_brgen_vertical_surfaces.scss` (2,210) worst; then
  `_brgen_messenger.scss` (+59), `_brgen_marketplace.scss` (+39),
  `conversations/show.html.erb` (+41), `_brgen_dating.scss` (+82),
  `_brgen_feed_posts.scss` (+18), `_minimal.scss` (+6), `seeds.rb` (+2),
  `application_helper_test.rb` (+4), `user_purge_job_test.rb` (357, no row),
  `_brgen_core_shell.scss` (480, no row), `posts/show.html.erb` (164, no row),
  `listings/show.html.erb` (+1), playlist `_player.html.erb` (159, no row).
  Splitting them is real work against files their authors are actively
  editing; each split lowers its row.
- [ ] `method_length_ratchet_test.rb`: brgen carries 11 methods over 30 code
  lines against a ceiling of 8, and its longest is 71 lines against 51. Same
  law: split at the responsibility bound, lower the numbers.
- [ ] `weight_kb` in `css_budget.yml` was seeded 2026-08-31/09-25 and the
  shared engine's stack has grown since; amber's compiled build measured
  157KB against a 103KB ceiling in this sandbox. The build is gitignored, so
  the honest re-measure belongs to a checkout that can precompile — raise
  only with every added kilobyte named, per the file's own record.

## model pool — free compute and never-modelless (researched 2026-11-06)

Research against openclaw.ai (394k stars, MIT) and the free-tier landscape
surfaced verified additions for MASTER's lanes. Verified live same-day: Kilo
gateway (https://api.kilo.ai/api/gateway, model openrouter/free, keyless) and
OVHcloud AI Endpoints (https://oai.endpoints.kepler.ai.cloud.ovh.net/v1,
keyless, 2 RPM per IP per model, 20+ models). GitHub Models retired 2026-07-30;
Gemini free tier hides its numbers; Hugging Face free monthly credits are gone.

- [ ] PARTIAL 2026-11-10: `Io::ModelQuota` now parses `free_model_daily_requests` (`used`/`limit`/`remaining`), retains sample freshness and uses key-wide local fallback; quota suite NOT_RUN and live credential probe NOT_RUN.
- [ ] PARTIAL 2026-11-12: the free-floor savior now requires both a run-local
  successful non-free provider receipt and `LaneState.usable?`; configured
  binaries/keys are not proof. The `RunPulse` consecutive-death streak resets
  on success and counts free/local failures only; the process-local floor
  counter resets only on a free/local success. Source review (2026-11-12)
  confirms that `PassRunner#probe_lanes_once` uses `LaneProbe.run`, and
  `LaneProbe.pick` calls `LaneSelection.order`: dead/parked lanes are filtered
  by lane-state checks, and a suspended free/local floor inherits class rank 9.
  Existing tests cover the rank and probe capacity separately; a new
  cross-boundary regression pins the handoff. The instrumented pass-0 runtime
  walk remains NOT_RUN, so do not claim runtime acceptance or change the
  reservation policy from source inspection alone. The probe deliberately
  retains a bounded free/keyless reservation so it can detect floor recovery.
- [ ] Rank free-load selection by latency: the live-`:free` spread with
  per-model quota buckets landed 2026-11-06, but the catalog carries no
  `free_latency` field, so ranking stays pool order until one exists.
Ollama Tier-D remains excluded under the operator's current no-Ollama model-pool decision. Revisit only after access is restored and the operator reopens that lane.

## simplicity-book laws (candidate batch, researched 2026-11-06)

laws.yml already cites Rams, Strunk & White and NN/g. The uncited,
machine-checkable simplicity canon yields a deterministic first batch; the
rendered or task-evidence canon waits for the screenshot workflow.

- [ ] TUFTE_DATA_INK_RATIO: erase non-data ink — decoration-to-content ink measured in CSS decoration rules and chart ink versus data ink.
- [ ] GESTALT_PROXIMITY: grouping distance must be smaller than separation distance on a rendered surface (screenshot geometry pairs with the layout-refinement workflow).

## /fix law batch — Gemini candidate research (landed 2026-11-07)

The ranked candidate list from the model council research — the biggest gains
from narrow, low-risk normalisers, the rendered tier behind CDP, and the
behaviour-changing rewrites routed to the model council, never the autofix
pass — landed as sixteen Law.define declarations plus one detector extension,
with catalogue rows in laws.yml and the house-policy thresholds in
laws.yml. Static proof on this host (no Ruby interpreter available):
every bad/good fixture pair verified against a 1:1 Python port of each
detector and evaluator (14 of 14), structural parity of every touched Ruby
file against git HEAD, and a LawCataloguePreflight simulation mapping all
sixteen ids to their entries. Runtime proof — rake dogfood, test_law_fixtures,
test_law_parity, the rendered suite in headless Chrome — is NOT_RUN from this
sandbox and folds into section 1's Current-revision acceptance.

- [ ] Verify on the installed compatible Ruby: rake dogfood green over law/, test_law_fixtures, test_law_ids_unique, test_law_parity and the test_law_catalogue* family green, and one rendered-suite pass per new snapshot Law in headless Chrome.
  PARTIAL 2026-11-07: test_law_fixtures (8 runs) and the catalogue family (test_law_ids_unique, test_law_parity, test_law_catalogue + bootstrap + policy, 6 runs) are green on the pinned 4.0.5 host. rake dogfood (writes) and the headless-Chrome rendered pass remain NOT_RUN.
- [ ] Apply REDUNDANT_CORE_REQUIRE's fix — the 108 dead requires — through /fix with MASTER_AUTOFIX=1, not by hand.
- [ ] Tune design_thresholds against measured surfaces once the rendered suite runs: the 0.02 OKLab merge distance and the APCA levels are starting levels, not standards.

## pub5 migration record

The phased rewrite proposal from 2026-11-04 was superseded by the operator's
2026-11-07 instruction. pub5 was created as a direct carry from pub4
`main@f827973a7631be5f73e227864223ab2b6e7aee9b`, with a fresh history;
`BPLANS/` became `BIZ/`. The migration did not follow the proposed Phase 0–5
sequence, so those phase checkboxes were not evidence of unfinished work and
are retired here. The route, rendered, data-round-trip and CLI acceptance
requirements remain open only where they are already represented in the
active acceptance sections above.

The migration note recorded several exclusions. These are the carry-over
items still needing a disposition; none should be restored blindly or placed
back at the repository root:

- [ ] **Ragnhild artist-grant application PDF.** The separate five-page guide
  is restored and date-reviewed in `BIZ/ragnhild/ragnhild_legater.html`.
  Unverified BKV 2027 dates from the archive were removed; NBK had not published
  confirmed 2027 project-support dates on 8 November 2026. Bergen's professional
  art/culture deadlines and the Fegerstens eligibility/cycle were checked
  against primary pages. No PDF existed in pub4; render the restored HTML and
  visually inspect pagination, links and text before declaring the deliverable
  complete.
- [x] **Merethe LoRA preparation restored at the canonical path.** The
  recovery/preflight package and its test now live under `STUDIO/lora/merethe/`.
  Its preparation command moves only known local, ignored subject data from the
  previous `STUDIO/replicate/lora/merethe/` path and refuses symlinks or
  destination collisions. Paid training and source-rights decisions remain
  separate gates in §8.10.

The one-shot legacy archive-extraction helper was also intentionally excluded.
The pub4 repository remains the read-only provenance source; do not revive
its old tree wholesale. Historical MASTER face files and OpenBSD/RAILS files
that were replaced by newer owners should be assessed through the active
convergence and acceptance rows, not copied back by path similarity.
