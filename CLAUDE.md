# CLAUDE.md

MASTER is Claude's #1 primary configuration for this repository. This file
is the one hand-written bootstrap pointer; it holds no policy of its own.

Before planning or acting, read the root `AGENTS.md`. Gemini, GLM and Cursor
entry files point there; Copilot reads it directly. The shared contract is
generated from `MASTER/AGENTS.md`. The shared tree contract matrix is
`MASTER/data/law/TREE_CONTRACTS.md`; RAILS, MASTER/web and OPENBSD requirements
are recorded there. Claude's project hooks remain available
at the native `.claude/settings.json` path.

## First three commands

From the repository root, after reading `AGENTS.md`:

1. `ruby MASTER/tools/agent_context.rb --json` — load current task context and checks.
2. `MASTER/bin/operator doctor` — inspect checkout and host readiness.
3. `MASTER/bin/master --help` — read the current command surface.

`MASTER/data/soul.yml` is the highest source for global identity,
preservation, source order and protected paths. `MASTER/data/laws.yml`
owns individual Law identities and statements; the executable Law Ruby in `MASTER/law/`
and `MASTER/checks/` implements and verifies them.
