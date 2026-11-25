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
- [Marketplace, Takeaway and Brgen's other verticals](RAILS/brgen/README.md) — local commerce and food ordering.
- Dating, Messenger, Maps, Radio, TV, Marketplace and Takeaway are distinct Brgen services, documented in the [Brgen project guide](RAILS/brgen/README.md).
- [Mr. Damascy](RAILS/mrdamascy/README.md) — the standalone Bergen restaurant ordering app.
- [BIZ](BIZ/README.md) — evidence-backed business, funding and professional documents.

Engineering and agent-facing guidance is written in English. Customer-facing
products are Norwegian-first, with English where the app's locale support is
implemented. BIZ documents use the language and conventions of their intended
reader.

## Repository shape

```text
pub5/
├── MASTER/   constitution, agent runtime, Laws and /fix
├── RAILS/    Brgen, Amber, BSDPorts and product applications
├── OPENBSD/  vm23, DNS, relayd and operator deployment
├── STUDIO/   music, image and media-production tools
└── BIZ/      business plans and professional documents
```

The four runtime trees have executable checks and operational owners.
`BIZ/` is the fifth content root: one folder per workstream with its
published pair or editable source; shared bases, build/check/print tools,
templates and research live under `BIZ/tools/`.

Start with [MASTER](MASTER/README.md), [RAILS](RAILS/README.md),
[OPENBSD](OPENBSD/README.md), [STUDIO](STUDIO/README.md) or
[BIZ](BIZ/README.md), depending on the work.

## Documentation standard

Maintained Markdown follows one house method: Strunk and White for clear
sentences, Bringhurst for hierarchy and typographic restraint, and OpenBSD
documentation practice for precise, maintained, testable instructions. Product
copy may keep its own voice; technical claims, commands and evidence remain
literal. The full editorial contract lives in [MASTER/AGENTS.md](MASTER/AGENTS.md).

## Start by role

| Role | Start here |
| --- | --- |
| Operator | `MASTER/README.md` and `MASTER/bin/operator` |
| Agent or contributor | `AGENTS.md`, then the owning tree or product entrypoint below |
| Deployer | `OPENBSD/RUNBOOK.md` |
| Writer or plan maintainer | `BIZ/README.md` |

## Tree and product entrypoints

| Scope | Maintained entrypoint |
| --- | --- |
| MASTER | `MASTER/AGENTS.md` and `MASTER/README.md` |
| RAILS | `RAILS/CLAUDE.md`, `RAILS/README.md`, then the target app or engine README and any local `AGENTS.md` |
| OPENBSD | `OPENBSD/CLAUDE.md`, `OPENBSD/RUNBOOK.md` |
| STUDIO | `STUDIO/README.md` and the target tool's README |
| BIZ | `BIZ/README.md` and the target workstream's source/production profile |

Do not assume every tree has an `AGENTS.md`: use the maintained entrypoint
for that boundary, then read any narrower app, engine or workstream contract.

## Agent entrypoints

`AGENTS.md` is the shared contract generated from `MASTER/AGENTS.md` by
`cd MASTER && rake docs:agent_contracts`; verify it with
`rake lint:agent_contracts`. Do not edit generated pointers directly.

| Agent | Entry file | Role |
| --- | --- | --- |
| Codex and Copilot | `AGENTS.md` | Read the complete shared contract directly. |
| Gemini CLI | `GEMINI.md` | Generated pointer to `AGENTS.md`. |
| GLM | `GLM.md` | Generated pointer to `AGENTS.md`. |
| Cursor | `.cursorlaws` | Generated project-specific pointer to `AGENTS.md`. |
| Claude Code | `CLAUDE.md` | Hand-written bootstrap; routes to `AGENTS.md`. |
| Aider | `.aider.conf.yml` | Loads the canonical policy files; automatic commits are disabled. |

The pointer files do not carry independent policy. Edit their source in
`MASTER/AGENTS.md` and regenerate them together. `.cursorlaws` is Cursor's
local entrypoint name, not a second Law catalogue. Aider's file list explains
what it reads; the operator remains responsible for commits.

`MASTER/lib/convergence/architecture.rb` reports the live cross-tree inventory; `MASTER/data/law/TREE_CONTRACTS.md`
is the shared runtime/tree contract. `BIZ/README.md` owns BIZ's document-production workflow. Open work lives with its
owner: `MASTER/convergence.yml`, `MASTER/data/gaps.yml`,
`MASTER/data/operator_seams.yml`, `MASTER/data/law/ux_refinements.yml` and
`RAILS/refinements.yml`. `bin/master status --agent` is their read-only union;
there is no parallel Markdown checklist or generated backlog.

## First hour

For a disposable sandbox without Ruby, Chrome, libvips or root, run
`MASTER/bin/sandbox-bootstrap` and source `MASTER/bin/sandbox-env`.
Use `--dry-run` to inspect the plan. Skip this step on a machine that already
has the required stack.

For normal host setup, diagnostics and the first repair, follow the canonical
[MASTER first-hour and failure guide](MASTER/README.md#doctor-first-hour-and-failures).
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

`VERSION` records the release line. The retired full-rule corpus declared itself `not_a_live_config`; its
covered requirements now live in `MASTER/law/` and `MASTER/data/laws.yml`. The working master of the FETAT
proposal (a document, not policy) lives at `BIZ/tools/fetat_proposal.md`.
The workstation deploy interface is `MASTER/bin/operator vps deploy <app|group|all> --remote`;
the on-box serial deployment engine is `OPENBSD/bin/vps-deploy`.

Security reports should follow the private-disclosure path in [SECURITY.md](SECURITY.md);
do not publish unremediated vulnerabilities in public issues.
