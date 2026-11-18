# pub5

**pub5 builds and governs Brgen and its sister products, their OpenBSD operations, creative tooling and professional documents in one evidence-led repository.**

One checkout holds four runtime trees and a fifth BIZ content root. The model
only proposes. **Soul** is the global constitution: it defines identity,
preservation, source precedence and protected paths. The **Law catalogue**
contains individually named requirements that executable checks, tree
contracts and reviews apply to changes. **INCONCLUSIVE** means the available
evidence does not establish an outcome; it is never a passing result.

## Products

- [Brgen](RAILS/brgen/README.md) — the city-first social network and host for its verticals.
- [Amber](RAILS/amber/README.md) — a private wardrobe and style companion.
- [BSDPorts](RAILS/bsdports/README.md) — search and inspect the OpenBSD ports tree.
- [Marketplace](RAILS/brgen/engines/marketplace/README.md) and [Takeaway](RAILS/brgen/engines/marketplace/engines/takeaway/README.md) — local commerce and food ordering.
- [Dating](RAILS/brgen/engines/dating/README.md), [Messenger](RAILS/brgen/engines/messenger/README.md), [Maps](RAILS/brgen/engines/maps/README.md), [Radio](RAILS/brgen/engines/radio/playlist/README.md) and [TV](RAILS/brgen/engines/radio/tv/README.md) — Brgen's distinct city services.
- [Mr. Damascy](RAILS/mrdamascy/README.md) — the standalone Bergen restaurant ordering app.
- [BIZ](BIZ/README.md) — evidence-backed business, funding and professional documents.

Engineering and agent-facing guidance is written in English. Customer-facing
products are Norwegian-first, with English where the app's locale support is
implemented. BIZ documents use the language and conventions of their intended
reader.

## The four runtime trees

- `MASTER/` — the constitution, the runtime and the instruments: the Law
  catalogue, the scanner, the single `/fix` pipeline (with compatibility mode aliases),
  and the operator and agent entrypoints. Start at `MASTER/README.md`; the workflow contract is
  `MASTER/AGENTS.md`.
- `RAILS/` — the applications and their shared engine, with the deploy
  tooling that carries them. Start at `RAILS/README.md`.
- `OPENBSD/` — the vm23 deployment tree: VPS configuration under `etc/`,
  `usr/` and `var/`, DNS, relayd, and the operator scripts. Live work starts
  at `OPENBSD/RUNBOOK.md`.
- `STUDIO/` — the media tools: Dilla, photograph and the Replicate client.
  `STUDIO/Rakefile` is the tree's check surface.

## Fifth content root: business and writing deliverables

`BIZ/` holds the business plans as one tree (merged from BPLANS and
MASTER/tools/biz on 2026-11-08): one folder per plan with its published
pair, and the bases, build/check/print chain, templates, research and
proposals in `BIZ/tools/`. The canonical guide is `BIZ/README.md`.

## Start by role

| Role | Start here |
| --- | --- |
| Operator | `MASTER/README.md` and `MASTER/bin/operator` |
| Agent or contributor | `AGENTS.md`, then the target tree's `AGENTS.md` |
| Deployer | `OPENBSD/RUNBOOK.md` |
| Writer or plan maintainer | `BIZ/README.md` |

## Agent entrypoints

`AGENTS.md` is the canonical agent entrypoint and carries the shared workflow
contract generated from `MASTER/AGENTS.md`. Gemini, GLM and Cursor have short
generated pointers to it; Codex and Copilot read it directly. `CLAUDE.md` is
the bootstrap pointer.
`MASTER/lib/convergence/architecture.rb` reports the live cross-tree inventory; `MASTER/data/law/TREE_CONTRACTS.md`
is the shared runtime/tree contract. `BIZ/README.md` owns BIZ's document-production workflow. Root `TODO.md` is the one cross-tree
action list; structured YAML ledgers remain the owners of IDs, evidence receipts,
provenance and lifecycle state. Do not create another backlog file.

## First hour

In a container with no Ruby, no Chrome, no libvips and no root — a sandbox,
a CI image, a fresh machine — do not improvise the setup: run
`MASTER/bin/sandbox-bootstrap`, which builds the vendored Ruby, installs
every tree's bundle, extracts the libvips `.deb` closure, installs Chrome
for Testing and the two gems the bare-ruby suites need, then strips the
interpreter pin bundler writes into the lockfiles. Source
`MASTER/bin/sandbox-env` in the shell that follows it. `--dry-run` prints
what it would do without doing it. On a machine that already has the
stack, skip it.

Use an installed Ruby 3.3 or newer and run `bundle install` in
`MASTER/`. Keep API keys in the environment, never in Git. Run
`MASTER/bin/operator doctor` for checkout/host readiness and
`MASTER/bin/doctor` for MASTER runtime/provider/voice readiness. They are
different read-only reports. Then take one narrow dry run from `MASTER/`:

```text
bin/master '/fix --dry-run --critique --only critique,map MASTER/lib/cli'
```

Read veto, INCONCLUSIVE and skip lines as failures of proof, never as success. Deploy only
through the OPENBSD runbook path. Commit path-scoped changes to main; never force-push.

## Source authority and Laws

`MASTER/data/soul.yml` owns global identity, preservation principles,
source precedence and `absolute.sacred_paths`. The hierarchy is intentionally
one-way:

```text
Soul (`soul.yml`)
  ↓
Law catalogue (`laws.yml`)
  ↓
Executable Laws and gates
  ↓
Tree contracts
  ↓
Git history
```

The Soul answers what must remain true. The Law catalogue gives each
requirement one identity. Executable Laws and gates measure or constrain
changes; tree contracts define each tree's local boundary; Git history records
what happened, but cannot overrule current authority.

`MASTER/data/laws.yml` is the one catalogue of individual Law identities,
statements, parentage and the nine invariant nodes' internal order, together
with the scanner, veto, plugin and `/fix` runtime configuration. A missing or
unrun measurement is INCONCLUSIVE, never PASS.

## Repository facts

`VERSION` records the release line. The retired `FULL.yml` rule corpus declared itself `not_a_live_config`; its
covered requirements now live in `MASTER/law/` and `MASTER/data/laws.yml`. The working master of the FETAT
proposal (a document, not policy) lives at `BIZ/tools/fetat_proposal.md`.
The workstation deploy interface is `MASTER/bin/operator vps deploy <app|group|all> --remote`;
the on-box serial deployment engine is `OPENBSD/bin/vps-deploy`.
