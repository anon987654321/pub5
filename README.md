# pub5

**One checkout, four runtime trees, a fifth BIZ content root, and a written source hierarchy that outranks every
agent working in any of them.** pub5 is a self-governing repository: the model
only proposes; Soul defines global identity, preservation, source order and
protected paths, while the Law catalogue defines the requirements each change
must satisfy.

## The four runtime trees

- `MASTER/` — the constitution, the runtime and the instruments: the Law
  catalogue, the scanner, `/fix`, `/review`, `/critique`, and the operator and
  agent entrypoints. Start at `MASTER/README.md`; the workflow contract is
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

## How to enter

`AGENTS.md` is the canonical agent entrypoint and carries the shared workflow
contract generated from `MASTER/AGENTS.md`. Gemini, GLM and Cursor have short
generated pointers to it; Codex and Copilot read it directly. `CLAUDE.md` is
the bootstrap pointer.
`MASTER/data/law/TREE_CONTRACTS.md` is the shared runtime/tree contract; `BIZ/README.md`
owns BIZ's document-production workflow. Root `TODO.md` is the one cross-tree
action list; structured YAML ledgers remain the owners of IDs, evidence receipts,
provenance and lifecycle state. Do not create another backlog file.

## First hour

Install Ruby 3.3 or newer (below 4.1; `.ruby-version` pins 4.0.5) and run `bundle install` in
`MASTER/`. Keep API keys in the environment, never in Git. Run `MASTER/bin/doctor` and read its
one-line reports. Then take one narrow dry run from `MASTER/`:

```text
bin/master '/fix --dry-run --critique --only critique,map MASTER/lib/cli'
```

Read veto, INCONCLUSIVE and skip lines as failures of proof, never as success. Deploy only
through the OPENBSD runbook path. Commit path-scoped changes to main; never force-push.

## Source authority and Laws

`MASTER/data/soul.yml` owns global identity, preservation principles,
source precedence and `absolute.sacred_paths`. Its source hierarchy is:

`soul.yml > laws.yml > executable laws and gates > tree contracts > Git history`.

`MASTER/data/laws.yml` is the one catalogue of individual Law identities,
statements, parentage and the nine invariant nodes' internal order, together
with the scanner, veto, plugin and `/fix` runtime configuration. It does not
restate the source hierarchy or protected-path list. A missing or unrun
measurement is INCONCLUSIVE, never PASS.

## Repository facts

`VERSION` records the release line. The FULL.yml rule corpus was retired on
2026-11-02: it declared itself `not_a_live_config` and every one of its rows
in `MASTER/data/laws.yml` is marked covered — the constitution lives
in `MASTER/law/` and `MASTER/data/laws.yml`. The working master of the FETAT
proposal (a document, not policy) lives at `BIZ/tools/fetat_proposal.md`.
`redeploy` is the workstation deploy entrypoint.
