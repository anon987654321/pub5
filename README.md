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
  tree-path normalization (`MASTER/` -> `master/`, `RAILS/` -> `rails/`,
  `OPENBSD/` -> `openbsd/`, `STUDIO/` -> `studio/`, `PUB4_ROOT` -> `PUB5_ROOT`)
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

## Size ledger

Targets from the migration plan: total ~2,700-3,300 (master 700-900,
rails 1,800-2,200, openbsd 100-150, studio 40-50). Final landed counts are
recorded in the closing commit; where a tree lands above target, the excess
is itemized in `PORT_NOTES.md` with the behaviour-safe reduction candidates
that Phase 3-5 contract work still owes.

## Workflow

1. Read this file and `AGENTS.md` (the single shared contract).
2. Run `ruby master/tools/agent_context.rb --json [--tree <tree>]`.
3. State intent, scope, preservation, proof (`master/data/task_contract.yml`).
4. Work the owning tree with `master/bin/fix` (or `--dry-run` / `--strict`).
5. Commit path-scoped to `main` (`<tree>: summary`); leave evidence.
