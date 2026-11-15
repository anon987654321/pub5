# ARCHITECTURE — the map that saves an hour of grepping

README.md says what this repository *is*; Soul says who it obeys.

Scope note: each app keeps its own architecture record in its README
(amber's is read by a contract test, after an earlier root ARCHITECTURE.md
fell months behind because nothing read it). This file covers what those
records do not: the cross-tree layout, the shared machinery, the
environment the suite expects, and the working etiquette between sessions. This file is
the map a new session or a new human needs before the first command: where
things live, what couples to what, which environment variables the suite reads,
and the working etiquette that keeps several sessions from stepping on each
other. Every claim here is discoverable in the tree; the file exists so it does
not have to be rediscovered.

## The five trees

| Tree | What it is | Where its tests are |
| --- | --- | --- |
| `RAILS/` | The product family: `brgen` (host app + engines), `amber`, `bsdports`, `hjerterom`, the `__shared` engine all apps load, and `plugins/` | `RAILS/test/**/*_test.rb` via `ruby RAILS/test/run_all.rb` |
| `MASTER/` | The operator layer: `lib/operator/` machinery, `tools/` lints, `checks/` that ship to the box, the `web/` face | `MASTER/`'s own runners; RAILS contracts also read MASTER source |
| `OPENBSD/` | The vm23 box itself: `mirror/etc/` configs, `mirror/usr/local/bin/` installed helpers, rc scripts, cron | `OPENBSD/test/*_test.rb` |
| `STUDIO/` | The creative/rendering tree (face series, vendor assets) | its own tests |
| `BIZ/` | Business content root | content contracts |

Cross-tree reads are normal, not exceptional: a RAILS contract may assert the
shape of a MASTER tool, and the OPENBSD tests read the mirror scripts as text.
Changing a file in one tree can legitimately fail a test in another.

## The engine layout — read this before writing any glob

Brgen is the host for every vertical, and the verticals are Rails engines:

```
RAILS/brgen/engines/dating/
RAILS/brgen/engines/maps/
RAILS/brgen/engines/marketplace/
RAILS/brgen/engines/marketplace/engines/takeaway/   # twice-nested
RAILS/brgen/engines/messenger/
RAILS/brgen/engines/radio/{tv,playlist}/
```

Takeaway sits **two levels deep**. This has bitten the tree twice:

1. A single-level `engines/*/app/views` glob went blind to all five engines
   when they moved under `engines/<name>/` — the lint read the change as an
   80-finding improvement that was really 57 views disappearing.
2. A bare trailing `**` in a Ruby glob (`Dir.glob("brgen/engines/**")`)
   matches **one level**, so when takeaway nested under marketplace, the flash
   contract's locale merge never saw its files and reported
   `flash.takeaway.allergens_saved` as unresolvable while the mounted engine
   served it fine.

The rule, now encoded once in `EngineRoots`
(`MASTER/checks/support/brgen_vertical_surfaces.rb`):

- `**` followed by a path segment recurses; a bare trailing `**` does not.
- `EngineRoots.app_view_paths / app_controller_paths / app_locale_dirs` are
  the family-wide traversals; `engine_locale_dirs(rails_root, app)` is the
  app-scoped one.
- `RAILS/test/engine_layout_contract_test.rb` pins all of this. Do not write a
  new engine glob; use the traversal, and let the contract fail if the layout
  changes under it.

## What couples across the family

- `MASTER/tools/chrome_i18n_lint.rb` scans **every app's** views and
  controllers from one place. A hardcoded string added in a brgen view fails
  amber's CI. Its `BASELINES` are ratchets — zero is a ban, and the file's
  comment block records the full history of why.
- Locale files: every app and engine carries `nb.yml` + `en.yml` (and split
  domain files like `allergens.nb.yml`). Key parity between the two languages
  is contractual (`RAILS/test/locale_parity_test.rb`) and was found complete —
  keep it that way.
- `RatchetSponsor` (`MASTER/lib/operator/`) validates that a commit growing a
  measured population carries the ceiling that prices it (`MASTER/data/spine.yml`).

## Running things

```sh
ruby RAILS/test/run_all.rb                # the whole contract suite (~212 files)
ruby RAILS/test/run_all.rb --jobs 4       # four workers
ruby RAILS/test/run_all.rb scale          # files matching /scale/
ruby RAILS/test/run_all.rb --json out.json
ruby RAILS/test/run_all.rb --failed-from out.json   # rerun only the red
sh bin/bootstrap                          # ruby 3.4 + ksh + zsh into .tools/, idempotent
```

Environment variables the suite reads:

- `CONTRACT_TIMEOUT` — per-file seconds (default 300)
- `CONTRACT_REPLAY` — re-run passes N times with fixed seeds to catch flakes
- `PUB5_SUITE_ENV` — names the environment (`default`, `sandbox`); the ledger
  uses it to scope entries
- `PUB5_LEDGER=off` — skip ledger checking for an exploratory run
- `PUB5_ROOT` — exported by the box's `ci-run.ksh`; where contract helpers
  look first for the checkout (they fall back to the repo, then `/home/dev/pub5`)
- `PUB5_RUBY` / `PUB5_KSH` / `PUB5_ZSH` — interpreter overrides for the
  OPENBSD tests. The installed helpers and the tests keep their box paths as
  the default; a stripped checkout points these three at `bin/bootstrap`'s
  builds and the whole previously env-blocked half of the OPENBSD suite runs.

## The red ledger

`RAILS/test/known_failures.yml` registers every file the contract suite may
legitimately leave red, with a reason and an optional environment scope. The
runner fails on **an unregistered red** (a regression nobody accepted) and on
**a stale entry** (a file that went green while still registered). Registering
a red is not forgiving it: the reason line is the work order. Fix it or ratchet
it; do not delete the test, and do not let the file grow.

## Etiquette for concurrent sessions

More than one agent (or human) works this tree at once, and the history has
receipts of what goes wrong without a few habits:

- **Ratchet once, at the end of a session, on a settled tree.** A baseline
  recorded against a tree another session is still editing will read as a
  regression an hour later; the chrome_i18n comment block documents the day
  that cost amber a day of undeployed code. `chrome_i18n_lint --propose`
  prints the candidate move and the reminder; it never takes it.
- **Rebase before pushing; assume main moved while you worked.**
  `MASTER/lib/operator/replay_push.rb` exists because a rebase once refused a
  dirty tree holding another session's files.
- **Register your standing reds; fix them before the session ends if you can.**
  The ledger only works if every session treats an unregistered red as its own.
- **The failure messages are the documentation.** The tree's contract tests
  are written to explain themselves — if you add a test, make its message say
  what to do, not just what broke.
