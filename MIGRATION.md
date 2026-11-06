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
- pub4 remains a read-only archive. pub5's first commit names this source
  commit, per the port plan's conditions.
- The operator's instruction to build pub5 satisfies the plan's freeze
  condition ("the operator explicitly chooses to start a new tree"); pub4 is
  frozen for this port and stays archived afterwards.

## Structure of the port

pub5 carries the four governed trees. `BPLANS/` and `scripts/analysis/`
(document drafts and their crop/sheet tooling) are not part of the port; they
stay in the pub4 archive. Target shape from the plan: about 2,700–3,300 files
(MASTER 700–900, RAILS 1,800–2,200, OPENBSD 100–150, STUDIO 40–50).

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
  auth, embeds, PWA) stays the `pub4-shared` path gem.
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

## Functional renames in the port

These are functional wiring, renamed so pub5 is self-consistent:

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
- The `pub4-shared` gem name and `spec.authors = ["pub4"]` (provenance).
  Renaming the gem would churn every Gemfile and resolved require path for
  no behavioural gain; it is listed in `TODO.md` for the operator.
- Historical and finding ledgers that record where evidence was gathered
  (`MASTER/data/self_findings.yml` path rows were updated to the new layout
  because live drift tests read them against the current tree; narrative
  history documents were left as written).

## Evidence status (truthful)

The port environment had no Ruby toolchain (the trees pin Ruby 4.0.5; the
sandbox has none), no Rails boot, no vm23 access, and no browser. Therefore:

- Every suite in MASTER, RAILS, OPENBSD and STUDIO: **NOT_RUN** here. The
  acceptance commands in the port plan (`rake test`, `run_all.rb` per tree,
  `rake audit`, `bin/check --profile=agent`, the route contracts, golden
  screenshots) remain open work in `TODO.md` — they are the same items the
  pub4 backlog already listed as unresolved at the source commit.
- soul.yml / laws.yml byte-identity: **PASS** (verified by SHA-256 at the
  port commit).
- Engine-layout reference sweep: **PASS** for the enumerated reference
  sites (every `brgen_<vertical>` path reference found by repo-wide search
  was rewritten or reviewed; the remaining occurrences are identifiers,
  prose, history, or the deliberately-kept names above). Runtime behaviour:
  **INCONCLUSIVE** until the suites run on the pinned toolchain.
- The port did not delete behaviour to hit the plan's file budget; per-tree
  counts at the port commit are recorded in the delivery summary and the
  budget convergence work is listed in `TODO.md`.
