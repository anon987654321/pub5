# Migration record — pub4 → pub5

pub5 is a new repository built by porting pub4, not rewriting it: every
behaviour is locked as an executable contract, then rebuilt smaller against
that contract. This file records what the port carried, what it changed,
what it deliberately did not change, and what remains unproven. The plan it
executes is the "pub5 — a ported fresh start" section of the pub4 backlog
(`pub4:TODO.md`, archived in the pub4 repository at the commit named below).

Rule for the whole port: **same behaviour, less code; new features wait.**

## Source

- Repository: <https://github.com/anon987654321/pub4>
- Commit ported from: `3e70be37c8847300a191d13fd6b6e28ab888d7c9` (2026-11-06,
  "Show one dating header action and put the rest behind Mer")
- pub4 remains the source archive for the port. The first pub5 commit names
  the original cut; subsequent upstream changes are adopted only through an
  explicit, recorded catch-up, never by silently chasing `main`.
- pub4 landed five more commits on the same day (`3e70be3..d6fa34d`, still
  2026-11-06). They are ported as the catch-up below, so the port's source
  of truth moved to `d6fa34d7580214b80b588a08880d0f4439b37f41` at first;
  pub4 then landed `7caa03d` ("Let the marketplace hero lead with its copy
  when it has no photo") and, after that, `fdfe31d`, `2e47738` and
  `2c12470` (the consent-banner geometry, the messenger-rail guard and the
  shared chat label) — all ported the same way, each file byte-identical
  to its upstream state. The original port cutoff is `2c12470`. A later fetch found nine additional
  commits through `pub4@0a5ac0ce6c3e11bb8d9a1c040adf15b00acb3c6b` (2026-11-07);
  all nine are caught up below.

## Structure of the port

pub5 carries four governed code trees. The business-plan corpus moved on
2026-11-08 into the single `BIZ/` tree — published folders, the preserved
archive and the build tooling together (see "BIZ: one tree" below) — not a
fifth runtime owner. The old Python `scripts/analysis/` review helpers were intentionally not
carried as files: their screenshot-sheet capability is now owned by the Ruby
`MASTER/tools/visual/sheets.rb` implementation and its
`MASTER/test/test_visual_sheets.rb` contract. It uses the repository's
`ruby-vips` stack and avoids hard-coded checkout and crop paths. Target shape for the
four governed code trees remains about 2,700–3,300 files (MASTER 700–900,
RAILS 1,800–2,200, OPENBSD 100–150, STUDIO 40–50).

### Phase 1 — skeleton

- Root `README.md`, `AGENTS.md`, `TREE_CONTRACTS.md`, `TODO.md`, `VERSION`
  (2.0.0 — new release line; pub4 archived at 1.0.3), `.gitignore`,
  `.ruby-version` (4.0.5, reconciled with vm23), and `MIGRATION.md`.
- One lint configuration per family, as in pub4: the Rails family inherits
  one Omakase base (`RAILS/.rubocop.yml`), MASTER keeps its own. No new
  lint configs were added.
- One test command: `bin/test [tree]` dispatches to each tree's own runner.
- Commit-format hook from the first commit: `.githooks/` holds the four
  hooks pub4 kept under `OPENBSD/dev/githooks/`, adapted to pub5 paths and
  the `PUB5_*` environment namespace. They are installed by
  `MASTER/bin/operator hooks` (`core.hooksPath`), exactly as in pub4.
- Generated output stays outside git where pub4 already ignored it; tracked
  screenshot evidence was kept because checks still read it (see
  "Deliberately unchanged" below).

### Phase 2 — OPENBSD

- The vm23 tree is ported with its configs and the generator flow intact:
  `bin/render_dns.rb` generates the unsigned zones and `nsd.conf` from
  `data/dns.yml`, and the signed artifacts remain untracked by design, as in
  pub4.
- `OPENBSD/bin/deploy` is the one Ruby deploy entrypoint: it validates the
  app argument and hands off to the proven serial stages in
  `OPENBSD/bin/vps-deploy` (sync → CI → restart → health → stamp). The
  stages themselves are carried unchanged; rewriting 1,100 lines of live
  deploy zsh without a host to run it on would have been a claim, not a
  port.
- `OPENBSD/dev/githooks/` is gone: the hooks live at the root `.githooks/`.
- `dev/` workstation helpers and the operator scripts are carried.

### Phase 3 — RAILS

- Shared base carried: `RAILS/__shared` (tokens, SCSS foundation, Stimulus,
  auth, embeds, PWA) is the `pub5-shared` path gem; its gem identity follows
  the destination repository rather than retaining the retired pub4 name.
- Apps carried: `bsdports`, `mrdamascy`, `amber`, and the brgen core.
- **The structural change of the port:** each brgen vertical engine moved
  under `brgen/engines/` — `radio` (holding `tv` and `playlist` one level
  down), `dating`, `marketplace` (holding `engines/takeaway`), `messenger`,
  `maps`. pub4 had them as siblings of brgen; the pub5 layout is the one the
  checks already expected once (`brgen/engines/*`) before pub4 moved them
  out.
- Every discovered reference was rewritten: `brgen/Gemfile` and its lock,
  the engine-discovery globs in MASTER checks and fix tools
  (`EngineRoots`, `stimulus_wiring`, `engine_boundaries`, `dead_css_sweep`,
  `generate_route_manifest`, `payment_honesty`, `fast_stage`,
  `layout_search`), the test-scope globs (`Pub5TestScope`, `ci.rb`,
  `test_scope_parity_test`), the RAILS contract tests, `apps.yml`,
  `refinements.yml`, and the deploy copy-tree contract in
  `TREE_CONTRACTS.md`. The engines now sync inside the brgen app tree on
  vm23 (`/home/brgen/app/engines/<name>`), which the `app` sync mode
  carries; the `verticals` sync mode remains as a documented no-op so older
  runbooks stay truthful.
- Deploy tooling carried unchanged (`_*.sh`, `deploy.sh`, `bin/`).

### Phase 4 — STUDIO

- dilla, photograph, postpro and the Replicate client are carried.
- The Merethe subject-specific LoRA package (`replicate/lora/merethe/`)
  carries its recovery/preflight code, private-use instructions, environment
  example and tests. The 15 original subject photographs, derived dataset,
  ZIP and weights remain ignored local data; no image recovery, provider upload
  or paid training is performed by the migration.
- Screenshot contact-sheet generation is owned by MASTER through
  `MASTER/tools/visual/sheets.rb`; STUDIO does not keep a duplicate Python
  implementation of the same review workflow.
- `STUDIO/bin/studio` is the one CLI in front of dilla and postpro: a thin
  dispatcher to `dilla/dilla.rb` and the postpro entrypoints, so both tools
  are reachable through one command. `STUDIO/Rakefile` remains the tree's
  check surface.

### Phase 5 — MASTER

- `MASTER/data/soul.yml` and `MASTER/data/laws.yml` moved **byte for byte**;
  their SHA-256 at the port commit is recorded in the delivery summary.
- The runtime, instruments, Law detectors, checks, tools and `MASTER/web`
  are carried, with the hook path and engine-layout references updated as
  recorded above.

## Catch-up port — pub4 `3e70be3..d6fa34d` (2026-11-06)

After the phases above, pub4 received five more commits on the same day.
Each is a fix or a guard, not a new feature, so the "new features wait"
rule does not hold them back. Ported one upstream commit per pub5 commit,
with every ported file byte-identical to pub4@d6fa34d (verified by diff;
no rename, path or engine-layout adaptation was needed — the touched
paths carry over unchanged):

- pub4 `b85207f` → "Rails: show a live index's filter select inside the
  search pill" — `_search_yep.scss` keeps a live index's filter select
  visible inside the search pill (maps' place kind, amber's outfit
  filter), and the new MapPointListTest case proves it at `/places`.
- pub4 `896032c` → "Master: find each app at its apps.yml deploy_root when
  /fix checks the fleet" — `Reachability#verify_fleet!` resolves every
  app through `RailsApp.app_dir` (apps.yml `deploy_root`: brgen,
  MASTER/web, amber, bsdports, mrdamascy) instead of `RAILS/<name>`.
- pub4 `af6ae3d` + `d6fa34d` → "Rails: guard the nav counter pill's
  clearance from the top and its bar" — a system test at 1400 and 390 px
  holds the pill one 8px step below the viewport top and inside
  `.nav_swiper_bar`, with the `badgeBox()` probe; the lint blank line
  pub4 fixed in `d6fa34d` lands with the test here.
- pub4 `e4e08bd` → "Rails: space the dating header test from the test
  before it" — the blank line before the discover-header test in
  `dating_rewind_test.rb`. Whitespace only.
- pub4 `7caa03d` → "Rails: let the marketplace hero lead with its copy
  when it has no photo" — inside `_brgen_shared_overrides.scss`'s
  max-width block the `--empty` media well keeps its place after the copy
  (`order: 0; min-height: 0`), so a promoted listing without a photo no
  longer leads a phone with a 300px empty well; the new
  MarketplaceCheckoutTest case measures it at 390.
- pub4 `fdfe31d` → "Rails: keep the consent choices equal and above the
  floating chat pill" — `_cookie_banner.scss` gets equal auto-fit grid
  columns for the three choices on a phone (flex-end row from 768px) and
  sits one z-step above `--z-toast`, which the nearby-chat pill shares;
  the SharedChromeBehaviourTest case measures widths and reachability
  through real CDP device metrics at 390x844.
- pub4 `2e47738` → "Rails: hold the messenger rail to one letter per room
  with its full name" — a ChannelsControllerTest case holds every rail
  chip to a single capital with the full "#name" as its accessible name.
- pub4 `2c12470` → "Rails: give the shared chat widget's pairing label to
  every app" — `chat.random` moves from brgen's locales (where amber
  raised "Translation missing" on every page once it offered pairing) to
  the widget's own shared `social.{nb,en}.yml`, one owner, values
  unchanged.

The upstream `TODO.md` deletions in `af6ae3d`, `7caa03d`, `fdfe31d` and
`2e47738` (the nav-badge, marketplace no-photo, consent-banner and
messenger-rail backlog rows) have no counterpart here: pub5's TODO.md is
the port backlog, which never carried those rows.

Same evidence limits as the main port: no Ruby toolchain, so the new
tests are NOT_RUN here; they are carried as written upstream, where they
passed.

## Engine-glob catch-up (2026-11-06)

An independent audit of the port (searching every `brgen_*` wildcard and
`brgen_<vertical>` literal, not just the enumerated reference sites)
found a defect class the first sweep missed: discovery code that the
sibling layout survived inside as `brgen_*` globs and mixed brace lists.
Under pub5's layout no `RAILS/brgen_*` directory exists, so each glob
matched nothing and its check silently narrowed — the exact blindness
the verticals' first move taught this repo to fear (57 views, 71 pages).
Three commits fix all 22 files:

- "Master: point every engine discovery glob at brgen/engines" (14 files):
  user_flow's VIEW_PATHS and its marketplace source markers (the latter
  resolved `RAILS/brgen/engines/...` relative to `RAILS/brgen` and could
  only miss), dialect_purity, content_for_yield, dead_css_sweep's engine
  roots (takeaway sits one level deeper than radio's tv and playlist),
  baymard's source inventory, the restructure proof and CLI proof test
  discovery, runs.rb's brgen convention, page_inventory and
  design_metrics (whose half-rewritten brace lists had already dropped
  dating, messenger and maps from both simulations), coverage_map.yml,
  the restructure contract text, self_findings' census comment and
  AGENTS.md's Vertical definition.
- "OpenBSD: retire the ci-sync sibling-vertical loop the engine move
  emptied" (2 files): the copy loop over `RAILS/brgen_*/` matched
  nothing — the engines ride the app-tree rel list — and the contract
  test that asserted the sibling layout now asserts the engines in the
  rel list and walks every `path:` ref in each app's Gemfile.
- "Rails: point the family tests' engine walks at brgen/engines" (6
  files): i18n_resolution's engine census (the empty glob had removed
  every engine view from the keys-used scan), the path-idioms guard's
  pub4-era failure message, shared_chrome_source_contract's dead brace
  alternative, and three stale comments.

Everything now discovers engines through `EngineRoots`
(`MASTER/checks/support/brgen_vertical_surfaces.rb`) or its exact GLOB
shape. The remaining `brgen_*` occurrences are the deliberate keeps:
rails-sync's `verticals` mode (documented no-op), stylesheet module
names (`_brgen_marketplace.scss` et al.), and history.

## Functional renames in the port

These are functional wiring, renamed so pub5 is self-consistent:

- `pub4-shared` → `pub5-shared` and `pub4-rails-pwa` → `pub5-rails-pwa`;
  Gemfiles, lockfiles, deployment gates, operator metadata and active shared-engine
  source references now use the destination identity.
- `PUB4_ROOT` → `PUB5_ROOT`, `PUB4_RAILS_ROOT` → `PUB5_RAILS_ROOT`
  (48 + 25 sites; exported by `rc.d` and the deploy chain, consumed by
  `Shared::Contracts` and the operator tooling).
- The checkout path on vm23: `/home/dev/pub4` → `/home/dev/pub5` (199 sites)
  and `~/pub4` → `~/pub5` (15 sites). pub5's first deploy requires the
  operator to clone pub5 to that path; until then deploys refuse with a
  clear error rather than touching the pub4 archive.
- The commit-hook environment namespace `PUB4_*` → `PUB5_*` inside the four
  root hooks and the test that reads it.

## Deliberately unchanged (installed-state and provenance names)

These name state that exists on vm23 or provenance, and change only in the
operator's box cutover, not in a code port:

- `pub4-admin` (the installed `/usr/local/sbin` tool), the `pub4ci` group,
  `pub4_rcctl`, `pub4-signal*`, `pub4-alert*`, `pub4-dr`, `pub4-ci*`.
- `/var/log/pub4*`, `/var/db/pub4*` (log and state directories pinned by
  `newsyslog.conf`, `rc.d`, and the deploy stamps).
- The tmux session name `pub4-deploy` and the `PUB4_*` runtime flags other
  than the two renamed above.
- `spec.authors = ["pub4"]` in the shared gemspec (historical authorship provenance).
  The gem identity itself was subsequently migrated to `pub5-shared` across
  Gemfiles, lockfiles, deploy checks, and operator metadata.
- Historical and finding ledgers that record where evidence was gathered
  (`MASTER/data/self_findings.yml` path rows were updated to the new layout
  because live drift tests read them against the current tree; narrative
  history documents were left as written).

## Evidence status (truthful)

The working sandbox has Ruby 3.3.8 rather than the pinned Ruby 4.0.5, Node 22,
and `pdfinfo`, but no checkout mounted for execution, Rails dependency set,
Chromium browser, or vm23 access. Therefore:

- Every suite in MASTER, RAILS, OPENBSD and STUDIO: **NOT_RUN** here. The
  acceptance commands (`rake test`, `run_all.rb` per tree, `rake audit`,
  `bin/check --profile=agent`, route contracts and rendered screenshots)
  remain open in `TODO.md`. Ruby 3.3.8 is not the pinned 4.0.5 runtime, and no
  repository checkout or app dependencies are mounted for test execution.
- BPLANS Node syntax checks, its independent `bp_check.mjs`, PDF metadata and
  HTML/PDF render parity: **NOT_RUN**. Node and `pdfinfo` are present, but the
  source tree is not mounted and Chromium is unavailable.
- soul.yml / laws.yml byte-identity: **PASS**, re-verified by SHA-256
  against pub4@7caa03d (soul `44d9d6db…d067`, laws `821713cb…bec`).
- Engine-layout reference sweep: the original **PASS** claim covered only
  the enumerated sites and was too narrow — the follow-up audit (see
  "Engine-glob catch-up") found 22 more files carrying the sibling
  layout in `brgen_*` globs and mixed brace lists, now fixed. A full
  wildcard sweep after the fixes finds only the deliberate keeps:
  **PASS** for live discovery code, with runtime behaviour still
  **INCONCLUSIVE** until the suites run on the pinned toolchain.
- Per-tree tracked file counts at the engine-glob catch-up commits,
  against the plan's budget — all **OVER**, as the plan expected for a
  behaviour-preserving port (budget convergence stays in `TODO.md`):
  MASTER 2,597 (budget 700–900), RAILS 3,722 (1,800–2,200), OPENBSD 284
  (100–150), STUDIO 75 (40–50); total 6,678 against 2,700–3,300.
- Functional-rename sweep: **PASS** — 49 `PUB5_ROOT`/`PUB5_RAILS_ROOT`
  sites, zero functional `PUB4_ROOT`/`PUB4_RAILS_ROOT` leftovers (the
  only hit is this file's own rename record); the other `PUB4_*` names
  are the installed-state and provenance keeps listed above.


## Post-cutoff source catch-up — pub4 `2c12470..0a5ac0` (2026-11-07)

The port was compared against the live `pub4/main`, not assumed current from
the original migration note. Nine commits after `2c12470` were carried into
this snapshot:

- `958265b` — restore the traced Mr. Damascy mascot icon (SVG and raster/PWA
  assets).
- `db7e159` — keep Amber look titles within tile width and break only at words.
- `210bc62` — give the shared search hint AA contrast and pin BSDPorts' quiet
  update-age treatment.
- `ec05e5d` — retain the three RAILS rows as BLOCKED on missing operator input.
- `f827973` — restore seven historical root-level photographs, with their
  original Git blob IDs.
- `724c11b`, `f161d83`, `c5c34f6`, `0a5ac0c` — add Merethe LoRA curation
  instructions, guarded local preparation, environment template and preflight
  tests.

The RAILS style/test/icon changes and four STUDIO LoRA files were copied from
`pub4@0a5ac0`; the seven photographs and seven raster/icon assets were copied
as binary blobs. Each imported blob was checked against the source Git SHA.
The upstream `TODO.md` edits were not copied over the pub5 backlog; unresolved
work was merged into the one root `TODO.md`, while the completed pub5 phase
plan was removed.

## BIZ: one tree

The operator-requested archive landed at `BPLANS/` (41 source files and
7,314,428 bytes from `pub4@0a5ac0`: the seven then-current plan pairs, `ai3`
archive material, the `bob`, `bob2` and `bob3` historical HTML/PDF
templates, research notes, the Node authoring/check/print pipeline and the
Nosifer font; the import preserved source paths, file modes and Git blob
IDs, and the HTML and PDFs were not regenerated in transit).

On 2026-11-08 the operator merged the three business trees — `BPLANS/`,
the published `BIZ/` folders and `MASTER/tools/biz/` — into one `BIZ/`
tree: one folder per plan with its published pair, and the bases, build
chain, templates, research and proposals in `BIZ/tools/`. The same day's
orders merged NATO Aurora with the space domain into `future_nato_weapons/`
and added `future_healthcare_os/`, modelled on OpenBSD, Rails/Rhoda and the
MASTER trees. Where the copies disagreed, the superset won: the fixed
renders and the live toolchain stayed, the superseded renders and the stale
script copies were deleted, and `BPLANS/` no longer exists. The tree's own
verifier (`BIZ/tools/bp_check.mjs`) reports zero failures across all nine
published plans.

The three one-off Python scripts formerly in `scripts/analysis/` were not
copied into pub5. The current port tree owns this capability in
`MASTER/tools/visual/sheets.rb`, a Ruby/ruby-vips implementation with no
hard-coded capture paths or per-review crop lists, exercised by
`MASTER/test/test_visual_sheets.rb`. This is a deliberate toolchain and
ownership consolidation, not a silent loss of screenshot-review capability.

## Migration integrity snapshot

At staging time, every one of the 41 BPLANS source blobs matched its
`pub4@0a5ac0` SHA, as did all seven historical photographs and all 18
post-cutoff RAILS/STUDIO source files. The three old Python screenshot scripts are intentionally retired in favour
of the Ruby visual-sheet tool above. The
four governed code-tree acceptance suites, BPLANS check/build, rendered
screenshots, native OpenBSD validation and vm23 deployment remain
**NOT_RUN** or **BLOCKED** until executed in their required environments.
