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

pub5 carries four governed runtime trees (`MASTER/`, `RAILS/`, `OPENBSD/`
and `STUDIO/`) plus the fifth approved uppercase content root, `BIZ/`. The
business-plan corpus moved on 2026-11-08 into that single content tree —
published folders, the preserved archive and the build tooling together
(see "BIZ: one tree" below) — not a fifth runtime owner. The old Python `scripts/analysis/` review helpers were intentionally not
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

- dilla, photograph, postpro and the Replicate client are carried. Johann
  and Ragnhild subject profiles are restored under `STUDIO/lora/`; new graded
  portrait renders are private, flat files in that root.
- The Merethe subject-specific LoRA package (`lora/merethe/`)
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

- `pub4-admin` remains installed for compatibility callers; `pub5-admin`
  is installed alongside it and is the fixed broker used by the current
  `vps-deploy` path. The `pub4ci` group, `pub4_rcctl`, `pub4-signal*`,
  `pub4-alert*`, `pub4-dr` and `pub4-ci*` remain compatibility interfaces.
- `/var/log/pub4*` and `/var/db/pub4*` remain for legacy application,
  alert and state interfaces. The current deploy aggregate/per-run logs use
  `/var/log/pub5`; the current broker receipts use `/var/db/pub5`.
- The current deploy tmux session is `pub5-deploy`. Legacy `PUB4_*`
  runtime flags remain where the installed scripts still consume them.
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
post-cutoff RAILS/STUDIO source files.

**Later disposition — seven photographs (2026-11-10).** The seven phone
photographs were imported in `pub5@e2135dd`, then explicitly retired in
`pub5@616cf247` after review identified them as unassigned hand-drawn UI
sketches (post list, vote arrows, icon notes, an advertisement placeholder
and progressive-disclosure notes). No existing project owned them, and their
root-level paths violated the root inventory. This supersedes the earlier
"restore seven photographs" catch-up note: they are intentionally absent from
the current tree, not an untracked migration gap. Their source bytes remain
available in `pub4@0a5ac0` and pub5 Git history; do not restore them to the
repository root without a new owner decision.

## Current tree and constitution comparison — 2026-11-10

A recursive Git-tree comparison of `pub4@0a5ac0` and
`pub5@70dd962` used complete (non-truncated) GitHub tree responses:

- pub4: 6,749 tracked file entries; pub5: 7,205.
- 5,034 old entries retain the exact blob at the exact same path.
- 5,588 old file entries have an identical blob somewhere in pub5, including
  moved files; the largest relocation is the Brgen engine move.
- Of the 40 old RAILS files whose exact blob is no longer present, 39 have a
  corresponding file at the mapped `brgen/engines/` destination. The shared
  gemspec has the deliberate `pub4-shared` → `pub5-shared` identity change.
- The three old Python screenshot-sheet scripts have the Ruby
  `MASTER/tools/visual/sheets.rb` replacement. The STUDIO Python reference
  analyzer has the Ruby `STUDIO/dilla/lib/reference_analyzer.rb` replacement.
- OPENBSD's four former nested Git hooks moved to the root `.githooks/`.
  The seven root photographs are covered by the explicit retirement above.

This is a source/blob comparison, not behavioural acceptance: changed blobs
require their owning tests and runtime evidence. The measured counts do not
turn an intentional refactor, retirement or missing live test into a PASS.

The constitutional comparison found 154 Law identity rows at the pub4 cutoff
and 175 in current pub5. **All 154 old identities remain; 21 identities were
added.** This establishes identity preservation, not detector coverage or
runtime enforcement. The current `soul.yml` is intentionally not byte-identical
to the old file: the tree-contract source moved from root
`TREE_CONTRACTS.md` to `MASTER/data/law/TREE_CONTRACTS.md`, the old
`MASTER/data/law_runtime.yml` authority-order entry was removed, and the
2026-11-09 operator decree explicitly set `absolute.sacred_paths: []`.
That decree supersedes the old protected-path list; do not restore it from
history as a migration repair.

**Production server correction — 2026-11-11.** The migrated Mr Damascy
service's production Gemfile now uses Falcon 0.55.3; Puma remains only in the
test group for Capybara. Production starts through Falcon's documented host
interface, not the development-only `falcon serve` command: the tracked
`RAILS/mrdamascy/falcon.rb` config pins one worker to loopback HTTP/1, and
`preload.rb` loads the Rails environment before the worker starts. The rc.d
service invokes `falcon host` with that exact config path, and the OpenBSD
safety check enforces the command, process match, config, preload and dependency
split. Bundle resolution, focused Rails/OpenBSD tests and a vm23 restart remain
NOT_RUN until the pinned Ruby 4.0.5 host is available.

The three old Python screenshot scripts are intentionally retired in favour
of the Ruby visual-sheet tool above. The four governed code-tree acceptance
suites, BIZ check/build, rendered screenshots, native OpenBSD validation and
vm23 deployment remain **NOT_RUN** or **BLOCKED** until executed in their
required environments.

## Historical tree reconciliation — 2026-11-11

A second complete recursive Git-tree comparison was run against the recorded
pub4 cutoff and the current pub5 snapshot. Both GitHub tree responses were
complete (not truncated):

- pub4: `0a5ac0ce6c3e11bb8d9a1c040adf15b00acb3c6b`, 6,749 tracked blobs.
- pub5: `296121bb2b5fd540963b1bf57a27342e69377907`, 7,213 tracked blobs.
- 6,096 old paths still exist in pub5. Of those, 4,975 retain the exact old
  blob; 1,121 have changed contents at the same path.
- Another 549 old blobs survive byte-for-byte at a different path.
- The remaining 104 old blobs have neither their old path nor an identical
  blob elsewhere in pub5. They are accounted for by owner and disposition:

| Old source group | Count | Current disposition |
| --- | ---: | --- |
| `RAILS/` | 43 | Every old vertical-engine path has a current `RAILS/brgen/engines/` counterpart; `pub4-shared` has the `pub5-shared` gem identity. |
| `BPLANS/` | 29 | Consolidated into `BIZ/`; 28 path equivalents were checked. The old cover pass is superseded by `BIZ/tools/bp_retemplate.mjs`. |
| `MASTER/` | 16 | Backlog merged into root `TODO.md`; permission and creative-governance documents moved/renamed; research and repo tools moved under their owners; four unused legacy images retired; Smart Turn model/runtime binaries are checksummed build-time assets, not tracked files. |
| `OPENBSD/` | 4 | Nested Git hooks moved to root `.githooks/` and adapted to the pub5 environment namespace. |
| Historical root photographs | 7 | Explicitly retired on 2026-11-10 as unassigned sketches; not silently lost. |
| `STUDIO/` | 1 | Python reference analyzer replaced by the Ruby analyzer. |
| Root tree contract | 1 | Moved to `MASTER/data/law/TREE_CONTRACTS.md`. |
| `scripts/analysis/` | 3 | Python screenshot-sheet helpers replaced by `MASTER/tools/visual/sheets.rb`. |

The counts reconcile exactly: 4,975 unchanged at path + 1,121 changed at path
+ 549 identical blobs relocated + 104 explained retirements/replacements =
6,749 pub4 blobs. This is source accounting, not a behavioural PASS. The
Amber legacy manifest still accurately marks ML garment segmentation /
background removal and AI-generated closet tips as missing; the current
silhouette renderer and rule-based `ClosetOrganization` do not claim either
capability. The archived `pub_attorney` and `mytoonz` entries still require
an owner restore/retire decision. Neither omission was silently promoted to
an implementation.

The comparison does not change the acceptance status above. Focused tests
were added for the Mr Damascy secret privilege boundary, all documented
`/fix` aliases, and human escalation after three actionable repair refusals,
but they are authored tests, not passing test runs. The repository's full
MASTER, RAILS, OPENBSD and STUDIO suites, BIZ build/check, rendered browser
review, native OpenBSD validation and vm23 restart remain **NOT_RUN** or
**BLOCKED** until run in their required environments.

## Live migration reconciliation — 2026-11-11 (pub5/main@ff60792298f5d654cc7976fd9dfb3b8d4393d786)

The source-side check was repeated against pub4/main; it is still exactly
0a5ac0ce6c3e11bb8d9a1c040adf15b00acb3c6b, the recorded port cutoff. There
are no later pub4 commits to catch up.

A fresh, complete recursive Git-tree comparison used the pub4 cutoff and the
pub5 tree at ff60792298f5d654cc7976fd9dfb3b8d4393d786
(tree 823a0dc917d01a4ffbb986de93fa27492e543b0d). Neither tree response was
truncated:

- pub4: 6,749 tracked file blobs.
- pub5: 7,242 tracked file blobs.
- 4,830 pub4 blobs remain byte-identical at the same path.
- 1,253 old paths remain, but their contents have changed.
- 542 old blobs remain byte-identical at a different path.
- 124 old blobs have neither their original path nor an identical blob elsewhere.

The 124 non-identical/retired source blobs reconcile by owner and disposition:

| Old source group | Blobs | Current disposition |
| --- | ---: | --- |
| Root and MASTER runtime selectors, plus RAILS app selectors | 7 | The root .ruby-version, two MASTER pins and four RAILS app pins were retired. The current contract uses the installed compatible Ruby 3.3+ floor and runtime discovery; no patch-level pin or upper bound is authoritative. |
| BPLANS/ | 30 | Consolidated into BIZ/: plan folders own published pairs, templates and the authoring/check/print tools live under BIZ/tools/, the old NATO plan is merged into future_nato_weapons/, and the old cover script is superseded by bp_retemplate.mjs. |
| MASTER/ | 21 | Two runtime selectors are counted in the runtime-selector row above. The backlog became root TODO.md; dialogue policy moved to the voice owner; execution and visual policy were consolidated under the canonical Law catalogue; the permission matrix was renamed PUB5_PERMISSION_MATRIX.md; creative governance moved to MASTER/data/law/; research/repository tools moved under their owners. The four unused legacy face/hero images were retired. The old Smart Turn/ONNX runtime binaries are not tracked in the current tree; their replacement/download integrity is a runtime acceptance concern, not a reason to restore old binaries blindly. |
| OPENBSD/ | 4 | Nested hooks moved to root .githooks/ and were adapted to the pub5 environment and path contract. |
| Historical root photographs | 7 | Explicitly retired on 2026-11-10 as unassigned sketches, as recorded above. |
| RAILS/ | 47 | Four runtime selectors are counted in the runtime-selector row above. Dating, Maps, Marketplace/Takeaway, Messenger and Radio/TV sources moved into the consolidated RAILS/brgen/engines/ hierarchy. The shared gem identity changed from pub4-shared to pub5-shared; several source files evolved after the move rather than remaining byte-identical. |
| STUDIO/ | 3 | The Python reference analyzer was replaced by the Ruby analyzer. Merethe's preparation package moved to STUDIO/lora/merethe/ and was hardened; it is intentionally not byte-identical to the old location. |
| Root tree contract | 1 | Moved to MASTER/data/law/TREE_CONTRACTS.md. |
| Root redeploy shim | 1 | Replaced by the owned MASTER/bin/redeploy entrypoint. |
| scripts/analysis/ | 3 | Python contact-sheet/crop helpers were replaced by the Ruby/ruby-vips implementation at MASTER/tools/visual/sheets.rb. |

The accounting is exact: 4,830 unchanged in place + 1,253 changed at the same
path + 542 identical blobs relocated + 124 explained non-identical
replacements/retirements = 6,749 pub4 blobs. The earlier 2026-11-11 snapshots at pub5@296121b (4,975 / 1,121 / 549 / 104)
and pub5@5b19d609 (4,835 / 1,248 / 542 / 124) are historical and are
superseded by this live-tree count. Five files that were byte-identical at the
5b19d609 snapshot have since changed in place; no new paths were added and the
124 explained replacements/retirements are unchanged.

This is a file/provenance reconciliation, not behavioural acceptance. It does
not prove that changed RAILS behavior, runtime-fetched model assets, the
Ragnhild PDF, the BIZ build, browser rendering, full test suites, native
OpenBSD checks or vm23 deployment passed. Those gates remain exactly where
their owning rows in root TODO.md and the structured operator seams place
them. No pub4 tree or retired binary/photo should be copied back merely to
make blob counts match.

