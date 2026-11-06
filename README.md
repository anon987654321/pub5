# pub5

**One checkout, four trees, and a written source hierarchy that outranks every
agent working in any of them.** pub5 is a self-governing repository: the model
only proposes; Soul defines global identity, preservation, source order and
protected paths, while the Law catalogue defines the requirements each change
must satisfy.

pub5 is a ported fresh start from
[pub4](https://github.com/anon987654321/pub4), built by porting, not
rewriting: behaviours are locked as executable contracts, then rebuilt
smaller against them. The port record — what moved, what changed, what is
still unproven — is `MIGRATION.md`. pub4 stays as a read-only archive; the
first pub5 commit names the pub4 commit the port came from.

## The four trees

- `MASTER/` — the constitution, the runtime and the instruments: the Law
  catalogue, the scanner, `/fix`, `/review`, `/critique`, and the operator and
  agent entrypoints. Start at `MASTER/README.md`; the workflow contract is
  `MASTER/AGENTS.md`.
- `RAILS/` — the applications and their shared engine, with the deploy
  tooling that carries them. Start at `RAILS/README.md`. The brgen vertical
  engines live under `RAILS/brgen/engines/`.
- `OPENBSD/` — the vm23 deployment tree: VPS configuration under `etc/`,
  `usr/` and `var/`, DNS, relayd, and the operator scripts. Live work starts
  at `OPENBSD/RUNBOOK.md`; deploys enter through `OPENBSD/bin/deploy`.
- `STUDIO/` — the media tools: dilla, photograph, postpro and the Replicate
  client, behind the one `STUDIO/bin/studio` CLI. `STUDIO/Rakefile` is the
  tree's check surface.

## How to enter

`AGENTS.md` is the canonical agent entrypoint and carries the shared workflow
contract derived from `MASTER/AGENTS.md`. Gemini, GLM and Cursor have short
generated pointers to it; Codex and Copilot read it directly. `CLAUDE.md` is
the bootstrap pointer.
`TREE_CONTRACTS.md` is the one per-tree contract file. `TODO.md` is the one
cross-tree backlog; an item closes by being deleted in the commit that carries
its evidence.

## Source authority and Laws

`MASTER/data/soul.yml` owns global identity, preservation principles,
source precedence and `absolute.sacred_paths`. Its source hierarchy is:

`soul.yml > laws.yml > executable laws and gates > tree contracts > Git history`.

`MASTER/data/laws.yml` is the one catalogue of individual Law identities,
statements, parentage and the nine invariant nodes' internal order. It does not
restate the source hierarchy or protected-path list. `law_runtime.yml` remains
live transitional execution metadata; it is not a second normative Law
catalogue. A missing or unrun measurement is INCONCLUSIVE, never PASS.

## Working commands

- `bin/test [master|rails|openbsd|studio]` — one test command over the four
  trees' own runners; no argument runs all four in order.
- `bin/operator hooks` (from `MASTER/`) — installs the commit-format and
  shared-checkout guards from `.githooks/` (`core.hooksPath`).
- `./redeploy [all|brgen|amber|bsdports] [--follow|--detach]` — the
  workstation deploy entrypoint.

## Repository facts

`VERSION` records the release line (2.0.0 — the ported fresh start; pub4
archived at 1.0.3). The working master of the FETAT proposal (a document, not
policy) lives at `STUDIO/docs/fetat/proposal.md`.
