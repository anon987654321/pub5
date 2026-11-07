# pub5

**One checkout, four runtime trees, BIZ deliverables, and a written source hierarchy that outranks every
agent working in any of them.** pub5 is a self-governing repository: the model
only proposes; Soul defines global identity, preservation, source order and
protected paths, while the Law catalogue defines the requirements each change
must satisfy.

## The four trees

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

## Business and writing deliverables

`BIZ/` holds the published business plans and related documents. The canonical
editorial/build guide and editable source material live in
`MASTER/tools/biz/README.md`; generated plan pairs stay in their named `BIZ/`
folders.

## How to enter

`AGENTS.md` is the canonical agent entrypoint and carries the shared workflow
contract generated from `MASTER/AGENTS.md`. Gemini, GLM and Cursor have short
generated pointers to it; Codex and Copilot read it directly. `CLAUDE.md` is
the bootstrap pointer.
`TREE_CONTRACTS.md` is the repository's shared tree contract. Root `TODO.md` is
the one cross-tree action list; structured YAML ledgers remain the owners of
IDs, evidence receipts, provenance and lifecycle state. Do not create another
backlog file.

## Source authority and Laws

`MASTER/data/soul.yml` owns global identity, preservation principles,
source precedence and `absolute.sacred_paths`. Its source hierarchy is:

`soul.yml > laws.yml > executable laws and gates > tree contracts > Git history`.

`MASTER/data/laws.yml` is the one catalogue of individual Law identities,
statements, parentage and the nine invariant nodes' internal order. It does not
restate the source hierarchy or protected-path list. `law_runtime.yml` remains
live transitional execution metadata; it is not a second normative Law
catalogue. A missing or unrun measurement is INCONCLUSIVE, never PASS.

## Repository facts

`VERSION` records the release line. The FULL.yml rule corpus was retired on
2026-11-02: it declared itself `not_a_live_config` and every one of its rows
in `MASTER/data/law_runtime.yml` is marked covered — the constitution lives
in `MASTER/law/` and `MASTER/data/laws.yml`. The working master of the FETAT
proposal (a document, not policy) lives at `MASTER/tools/biz/fetat_proposal.md`.
`redeploy` is the workstation deploy entrypoint.
