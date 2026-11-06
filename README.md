# pub5

The from-scratch successor to pub4: a small trusted core, one registry per
concern, fewer and stricter Laws with proof, and /fix safe from its first
commit. See PLAN.md. Nothing here serves production yet; pub4 does.

The port carries the same behaviour in less code: every behaviour is locked
as an executable contract in pub4 first, then rebuilt here against that
contract. New features wait. pub4 stays as the read-only archive and holds
this port's working plan in its TODO.md ("pub5 — a ported fresh start").
The skeleton is ported from pub4 at 997af4779c (2026-11-06); the target is
about 2,700-3,300 files from about 6,000.

## The rule for every phase

- Lock the behaviour in pub4 before porting it: the route contracts,
  signed-in contracts, golden screenshots, Law proof fixtures, export/import
  round-trips and the CLI command contracts live in pub4's
  `MASTER/checks/` and `MASTER/test/` and pass against any base URL.
- Rebuild smaller against the contract. An app goes live here only when its
  contracts and screenshots pass against the ported app.
- `soul.yml` and `laws.yml` move byte for byte when MASTER is ported last,
  and pub4 MASTER governs until pub5 MASTER passes every Law fixture.

## Phases

0. Contracts locked in pub4 (route contracts and signed-in contracts landed;
   screenshots, Law fixtures, export/import, CLI contract and the one
   acceptance command follow).
1. This skeleton: README, `AGENTS.md` and PLAN.md, one Ruby version
   (`3.4.9`, reconciled with vm23, the deploy host), one lint command, one
   test command, the commit-format hook, generated output outside git.
2. OPENBSD - configs generated from `data/`, one Ruby deploy tool that ships
   a Mac-built artifact.
3. RAILS - shared base, then each app as in PLAN.md's architecture; going
   live requires passing contracts.
4. STUDIO - dilla and postpro behind one CLI.
5. MASTER - last; it governs pub4 until it passes every Law fixture here.

## Running what exists

- `bin/master` - the one entrypoint; `bin/master` alone lists its commands
  (registry/commands.yml). `bin/master --boot <command>` prints boot time.
- `bin/check` - the gate: parse (Ruby, YAML, JSON, ERB), enforced Laws, tests.
- `bin/lint` - the parse gate and enforced Laws; `bin/test` - the minitest
  suites under `test/`.
- `bin/setup` - once per clone: points git at `.githooks/` (pre-commit runs
  the gate on the staged bytes, commit-msg checks the subject).

Each is blind-tool proofed: a stage that measured nothing reports NOT_RUN
and fails, not a pass.
