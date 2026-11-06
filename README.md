# pub5

pub5 is the port of [pub4](https://github.com/anon987654321/pub4) into a smaller,
convention-first repository under the same constitution.

- Frozen pub4 oracle: `d6fa34d18779b54a7cff0d2d8cc1c904ed2502b2`
  (pub4 `main` at port time, 2026-11-06).
- Port model: **a port, not a rewrite.** Behaviour is locked in pub4 first,
  then rebuilt smaller against those contracts. pub4 becomes a read-only
  archive after cut-over.
- Constitution: `master/data/soul.yml` and `master/data/laws.yml` carry the
  same content as pub4. The only sanctioned textual delta is mechanical
  tree-path normalization (`master/` -> `master/`, `rails/` -> `rails/`,
  `openbsd/` -> `openbsd/`, `studio/` -> `studio/`, `PUB5_ROOT` -> `PUB5_ROOT`)
  required by the lowercase-tree layout. Original pub4 SHA-256 for every
  ported file is recorded in the port ledger (phase commits).

## Authority order

`soul.yml > laws.yml > executable laws and gates > tree contracts > git history`

- `master/data/soul.yml` — identity, preservation, protected paths, source precedence.
- `master/data/laws.yml` — the one catalogue of Law identities and statements.
- `master/data/law_runtime.yml`, `master/law/`, `master/checks/` — enforcement instruments.
- `TREE_CONTRACTS.md` and tree-local `README.md` — tree contracts below repo authority.
- Git history — provenance only, never an override.

## Command surface (flattened)

| Command | Role | Default |
| --- | --- | --- |
| `master/bin/scan [tree]` | observe only | never writes |
| `master/bin/fix [tree]` | governed write + converge | writes, normal intensity |
| `master/bin/fix --dry-run [tree]` | assessment only (old /review) | no writes |
| `master/bin/fix --strict [tree]` | higher-bar assessment (old /critique) | fails on blockers, runs to checks |

`master/bin/master` remains the full interactive runtime; the slash forms
(`/fix`, `/scan`) route exactly as in pub4. There are no `/review` or
`/critique` commands in pub5 — assessment intensity is flags on `/fix`.
No subcommands beyond this surface. Missing measurement is INCONCLUSIVE,
never PASS.

## Trees

| Tree | Owns | Entry |
| --- | --- | --- |
| `master/` | constitution, runtime, instruments | `master/bin/master`, `master/bin/operator` |
| `rails/` | apps and the shared sibling engine | `rails/deploy.sh` |
| `openbsd/` | deployment (vm23) — data in, config out | `openbsd/bin/deploy` |
| `studio/` | media tools (dilla, postpro, photograph, replicate) | `studio/bin/studio` |

Tree permissions live in each tree's `.pub5` marker (read / read_write per tree,
declared adapters). Path-scoped commits to `main`; never force-push.

## Port status (phase ledger)

| Phase | Scope | Status |
| --- | --- | --- |
| 0 | lock pub4 behaviour as contracts | source: pub4@d6fa34d is the oracle; fixtures ported with the trees |
| 1 | skeleton + commit 0 | this commit |
| 2 | `openbsd/` | ported: data/, bin/, lib/, checks/, test/, RUNBOOK; host mirrors (etc/usr/var/dev/home) are generated at deploy time and never committed |
| 3 | `rails/` | ported: shared engine (sibling), bsdports, mrdamascy, amber, brgen + engines, cross-app test oracle; per-app Phase-0 proof (contracts + golden screenshots) still gates "live" status |
| 4 | `studio/` | ported: one CLI over dilla + postpro, reproducible renders |
| 5 | `master/` | ported: constitution, flat law surface, fix kernel, flattened entrypoints |
| 6-7 | cut-over, soak, harden | pending operator |

## Port ledger — size accounting (final)

| Tree | pub4 | pub5 landed | pub5 target | Note |
| --- | --- | --- | --- | --- |
| root | 19 | 8 | ~8 | single AGENTS.md, no competing pointers |
| master/ | 2,595 | 1270 | 700–900 | web/, plugins/, voice/mobile/device/music/cognition/design libs and the old lib/review tree retired; checks incl. golden layout snapshots and the full flat law surface kept as the oracle |
| rails/ | 3,722 | 3616 | 1,800–2,200 | engines moved under brgen/engines/; per-app tests + migrations kept (behaviour oracle); further reduction is Phase-3 contract work per app |
| openbsd/ | 287 | 158 | 100–150 | etc/usr/var/dev/home host mirrors are generated at deploy time, never committed |
| studio/ | 74 | 74 | 40–50 | one CLI; archaeology notes retired |
| **total** | 6,735 | **5126** | ~2,700–3,300 | |

The landed total sits above the plan's estimate because the plan's per-tree
targets assumed cuts that only per-app Phase-0 contract work can prove safe
(migration squashes, per-app test consolidation, engine dedup). This port
keeps every behaviour oracle: constitution, laws, fixtures, golden layout
snapshots, per-app suites, check routers. The excess is itemized, not hidden.

Retired with the port (full lists in the phase commits and port ledger):

- root pointers: CLAUDE.md, GEMINI.md, GLM.md, .cursorlaws, BPLANS/, scripts/analysis, redeploy
- commands: `/review`, `/critique` (now flags on `/fix`); bin-level tts-worker,
  master-mobile*, device-*, cities, dogfood, spark, law-weight, tree-weight,
  nsaudit, provider-catalog, deploy-story, deps, domain-ghosts, verify-focused
- master lib: web/ (face chat), lib/review (parallel review tree), voice/,
  mobile/, device/, music/, cognition/, design/, ai/, visual/, plugins/
- openbsd: checked-in etc/usr/var/dev/home mirrors; install-era script family
- studio: ARCHAEOLOGY.md, LEGACY_RESTORE.md
- per-app AGENTS.md folded into app READMEs (one shared contract remains)

## Workflow

1. Read this file and `AGENTS.md` (the single shared contract).
2. Run `ruby master/tools/agent_context.rb --json [--tree <tree>]`.
3. State intent, scope, preservation, proof (`master/data/task_contract.yml`).
4. Work the owning tree with `master/bin/fix` (or `--dry-run` / `--strict`).
5. Commit path-scoped to `main` (`<tree>: summary`); leave evidence.
