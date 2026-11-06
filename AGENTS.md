<!-- pub5 shared agent contract. One entry point; no second navigation guide. -->

pub5 is governed by master/ under the same constitution as pub4. This text is
the shared contract for every agent working in any tree.

Workflow: one shared checkout; commit straight to `main` with path-scoped
commits (`<tree>: summary`); never force-push.

Before planning or acting, load the canonical context:

1. `master/data/soul.yml` is the highest source: identity, preservation,
   protected paths, source precedence. It does not create Law identities.
2. `master/data/laws.yml` is the one catalogue of individual Law records,
   statements, parentage, the ordered nine invariant nodes, and the
   `law_catalogue` execution metadata (severity, mode, lifecycle, autofix,
   language, surface, path exclusion).
3. At the start of every task run
   `ruby master/tools/agent_context.rb --json [--tree <tree>]` and consume
   `conduct`, `blocking_rules`, `coverage`, `task_contract_schema`,
   `capabilities`. It is the live working brief, not a replacement for the
   Law records.
4. For a Law-affecting task, read the Law row in `laws.yml`, its catalogue
   entry, its `Law.define` in `master/law/` and its bad/good fixtures or
   `proved_by` test. `master/data/law_runtime.yml` holds scanner, veto,
   plugin and /fix runtime configuration only — never per-Law policy.
5. Tree permissions: each tree's `.pub5` marker declares read / read_write
   per tree and any adapters (`master/contracts/*.rb`).

Source authority:
`soul.yml > laws.yml > executable laws and gates > tree contracts > git history`.

Command surface (the only verbs):

- `master/bin/scan [tree] [--json]` — observe only, never writes.
- `master/bin/fix [tree] [--dry-run] [--strict] [--json]` — the one governed
  writer. `--dry-run` is assessment without writes (old /review);
  `--strict` is the higher-bar assessment (old /critique): fail on blockers
  and run to checks. There is no `/review` or `/critique` command.
- `master/bin/master` — the full interactive runtime; slash commands route
  as in pub4.
- `master/bin/operator` — checks, tests, host operations (operator plumbing,
  not a second writer).

A missing or unrun measurement is INCONCLUSIVE, never PASS. A declaration,
an implementation, a passing test, and an excellent product are four
different claims.

Task entry: before a substantive edit, state intent, repository-relative
scope, mandatory preservation dimensions, and proof. Validate with
`Master::Fix::TaskContract`; schema in `master/data/task_contract.yml`.

**Existing-first structure.** Extend the nearest existing owner and its
tests before adding a tracked path; declare new paths and concrete reasons
in `TaskContract.new_paths`. Generated output (openbsd host trees, rails
build assets, studio renders, coverage, logs) is never committed — rebuild
on demand.

Task routing and minimum proof follow the owning tree contract in
`TREE_CONTRACTS.md`: master behaviour needs focused tests plus changed-line
Law assessment; rails behaviour needs app and browser proof; deployment
needs actual host output and health checks; studio media needs reproducible
output with seed/version retained.

On conflict, follow master/ and name the stale or contradictory file
instead of working around it in silence.
