# pub5 plan, draft 1 (2026-11-06)

Measured against pub4 `origin/main` at `bcc6e038da` (27,356 commits). Nothing was changed.

## 1. Measurements

| What | Number | Command |
|---|---|---|
| Text files and lines per tree | MASTER 2,580 / 456,410; RAILS 3,472 / 283,649; OPENBSD 287 / 31,786; STUDIO 74 / 17,510; BPLANS 29 / 7,109 | `git grep -I -c '' origin/main -- <tree>` summed with awk |
| MASTER by directory (files / lines) | lib 810 / 148,594; test 863 / 121,942; checks 254 / 55,864; web 266 / 49,893; data 93 / 26,742; tools 139 / 19,013; law 32 / 14,281; bin 30 | same, grouped by second path part |
| MASTER/lib subdirectories (files / lines) | fix 223 / 43,493; cli 103 / 19,156; review 79 / 14,563; io 87 / 14,536; voice 58 / 11,770; operator 55 / 10,668; ground 55 / 8,610; root 28 / 5,381; trace 28 / 5,122; core 6 / 2,416; boot 7 / 1,932; cognition 11 / 1,816; others under 1,200 each | same, grouped by third path part |
| RAILS by directory (lines) | brgen 91,627; __shared 53,588; test 33,606; amber 28,263; mrdamascy 17,139; brgen_marketplace 13,920; bsdports 10,449; brgen_radio 8,968; brgen_messenger 5,624; brgen_dating 2,713; brgen_maps 879 | same |
| Environment knobs | 462 distinct `MASTER_*` names in the repo; MASTER reads 495 distinct env names (325 of them `MASTER_*`) at 1,711 call sites | `git grep -h -o -E 'MASTER_[A-Z0-9_]+'`, plus `ENV[`/`ENV.fetch(` patterns |
| Laws | 520 catalogue entries; 514 `Law.define`; laws.yml is 4,208 lines with 282 top-level keys, 199 of them children. Lifecycle: 15 trusted, 8 advisory, 2 retired, the rest default | grep over `MASTER/data/laws.yml` and `MASTER/law/*.rb` |
| Laws that can run | 205 `ask` lines (judged by a model); executable bodies are 126 `check do`, 106 `detect`, 41 `< Detector` classes and 18 `pattern`, about 291 in total (they overlap, so this is an upper bound). Only 50 `proved_by` lines; 465 `good` examples | `git grep -h -E '^[[:space:]]+(ask|detect|check do|proved_by|good)'` in MASTER/law |
| Tests | MASTER 7,418 test methods in 851 files; RAILS 4,947; MASTER/web 180; OPENBSD 520; STUDIO 51 | `git grep -h -E 'def test_\|test "'` |
| Failing tests | The last recorded run (commit 79a7d00) covered only 287 runs: 6 failures in `test_fix_loop_file_collector.rb`, already failing before that commit. **The full suite has not been measured, so its status is unknown.** | `git show 79a7d00` |
| CI | None: no `.github/` in the tree. The only gate is an opt-in pre-commit hook (refuses cross-tree commits and Ruby that does not parse) | `git ls-tree -r origin/main \| grep .github` |
| Gems (declared / locked) | MASTER 31 / 100; MASTER/web 27 / 184; brgen 55 / 255; amber 43 / 240; bsdports 42; mrdamascy 19 | `grep -c '^\s*gem '` and Gemfile.lock specs |
| Largest files (lines) | RAILS/refinements.yml 6,346; interaction_campaign_400.json 5,703; laws.yml 4,208; three.face.module.js 4,114; runtime.yml 3,004; brgen vertical_surfaces.scss 2,954; amber application.scss 2,881; brgen shared_overrides.scss 2,825; design_tokens.yml 2,522; dilla.rb 2,475; law/universal.rb 2,396; tokens.yml 2,376; backlog.yml 2,372. Largest in lib: fix/kernel/lifecycle_journal.rb 1,403 | `git grep -I -c ''` sorted |
| Commits in 30 days | 10,959: anon987654321 8,821; gktepsta 1,942; Claude 88; Z User 77; MASTER 11; GLM 5; Z.ai 1 | `git log --since='30 days ago' --format=%an` |
| What breaks repeatedly (commit subjects, 30 days) | parse/syntax 177 (84 in the last 14 days); drift/contract 963; restore 275; writer/concurrent/race 229; rollback 36; revert 28 | `git log -i -E --grep=<pattern> --oneline \| wc -l` |
| Most-changed files (14 days) | refinements.yml 340; TODO.md 264; laws.yml 68; MASTER/README.md 66; brgen locales 63 each | `git log --name-only` |

**Duplicated abstractions found:**
- Five `proof.rb` files: lib/, core/, convergence/, cli/pipeline/, fix/restructure/.
- Four `session.rb` and four `benchmark.rb` files.
- Two copies each of `lane_silence.rb` (io/ and review/llm_dispatcher/), `soul.rb`, `ledger.rb` and `laws.rb`.
- 23 lib files use `Net::HTTP` directly.
- 77 call sites load YAML.
- 3 separate atomic-write implementations.
- Five model, provider or lane registries: models.yml, providers.yml, lanes.yml, inter_model.yml, operator_model.yml.
- Four enforcement engines: Laws (law/), checks (134 .rb files in checks/), ratchets (53 in operator/ratchets.rb) and house lint.
- Design tokens kept by hand across tokens.yml, the generated design_tokens.yml, `_dialect_tokens.scss` and `face.css :root`.
- Source and copy disagree: `vm_resource.yml` says it mirrors resource_guard.sh, yet notes "three recalibrations that never reached this file".

**What tonight showed:**
- `ASCII_PUNCTUATION` was applied to every tree, then withdrawn; undoing it took 6 restore commits.
- MASTER/web moved from RAILS/master back to MASTER/web.
- A per-run findings cap for /fix was added and reverted in the same second.
- Two parse breaks: mission.rb and Proof.
- /fix preflight was tripped by another writer's saves.
- Lane deadlines were split into a handshake budget and a read-idle budget, with a 30s, 1m, 5m wait ladder.
- The operator noted that GLM and Fable patches ran no tests and mostly did not hold against the code.
- Backups: backup_priv.sh documents that "Nothing had ever been backed up" because of four separate faults. Litestream and a restore script now exist.

## 2. Goals and non-goals

**Goals.**
- A small trusted core with explicit capabilities (in the spirit of OpenBSD's pledge and unveil).
- One canonical implementation and one registry per concern.
- Fewer, stricter Laws, each proven by fixtures.
- /fix safe from its first day.
- Zero loss of user data.
- Fits on vm23 (1 vCPU, 1 GB).
- Mobile-first, flat Swiss design driven by tokens, with chrome hidden until the reader moves.
- Ruby throughout, with data in YAML or JSON.
- Any result that was not measured is reported as INCONCLUSIVE or BLOCKED, never PASS.

**Non-goals.**
- Matching every pub4 feature on day one.
- Rewriting pub4's Laws by hand: they are imported mechanically (section 5).
- Keeping pub4's internal APIs.
- New product features during the migration.
- Python in the spine.
- Multiple production environments beyond a temporary rehearsal VM.

## 3. Keep verbatim, redesign, drop

**Keep verbatim:**
- Production SQLite databases and uploads (Active Storage).
- User accounts and password digests.
- Locales (en, nb) and their copy.
- soul.yml (reviewed once).
- The operator_* entries in project_context.yml.
- tokens.yml values.
- Domain facts from apps.yml.
- dilla's sound engine (dilla.rb and its data/*.json).
- The TTS voice engines (kept deliberately by the operator).
- The face mesh renderer, as a plugin.
- BPLANS content.
- pf, relayd and rc.d configurations that are proven in production.
- Litestream and restore scripts.
- Every pub4 Law: its laws.yml statement and catalogue entry and its Ruby (`Law.define`, detectors, fixtures), imported as advisory and re-qualified under §5.

**Redesign:**
- MASTER/lib, taking fix, review, cli and io from about 92,000 lines to a core plus plugins.
- RAILS/__shared as one shared engine; per-app SCSS overrides, now around 2,800 lines each, become token-only.
- Enforcement, as a single Law engine where checks and ratchets are kinds of Law.
- OPENBSD inventory, generated from one registry.
- The MASTER web face.

**Drop:**
- TODO.md (79 KB) and TREE_CONTRACTS.md (48 KB) as prose. They become backlog.yml and contracts that machines check.
- refinements.yml (6,346 lines, 340 edits in 14 days). It becomes Laws or backlog rows.
- The duplicate proof, session and ledger code; 23 direct HTTP callers become 1 client.
- More than 420 knobs.
- docs/history.
- reference_analyzer.py.
- Generated copies that nothing checks.

## 4. Target architecture

```
pub5/
  core/      ≤5k lines: World verbs (read, write, exec, net, llm, git, render), capability
             manifest checker, registry loader with schemas, atomic write, ledger
             (append-only JSONL), one HTTP/LLM client, config (knobs.yml), parse gate
  master/    agent runtime as plugins: cli, fix, review, voice, face, cognition, each with manifest.yml
  laws/      the Law engine, then one file per Law: detector, bad/good fixtures, proof test
  rails/     shared engine + brgen (dating, maps, marketplace, messenger, radio, tv as engines),
             amber, bsdports, mrdamascy
  openbsd/   rc.d, relayd, pf, deploy, rehearse; all generated from registry/apps.yml
  studio/    dilla, postpro, replicate
  bplans/
  registry/  apps, laws, models, knobs, tokens, commands, paths, writers, backlog (one each)
  bin/       master (the one entrypoint); check and setup are thin calls into it
```

**One entrypoint.** `bin/master` serves every surface: the terminal REPL, one-shot commands, /fix, the web face server, mobile and remote use, and scripts. pub4's separate binaries (bin/master, bin/operator, bin/fix-here, bin/spark, bin/check, bin/test, tts-worker and more) become commands. `bin/master` dispatches from `registry/commands.yml`, where each command names its plugin, the contexts it runs in and its capability manifest. It detects the context (tty, pipe, remote over ssh, web) instead of needing a binary per place, and boots only core plus the one plugin the command needs; `bin/master --boot <command>` prints the boot time.

**Capability boundaries.** Each plugin's manifest declares which World verbs it may use and which paths it may touch. Core refuses anything undeclared. Laws forbid `Net::HTTP`, `File.write` and `ENV[` outside core, and reading an environment variable that knobs.yml does not declare. A test per verb proves the refusal.

**Registries (one per concern).**
- `apps.yml` generates relayd, rc.d, the deploy inventory and memory budgets.
- `models.yml` merges the five model, provider and lane files.
- `paths.yml` holds path ownership plus protected paths.
- `writers.yml` holds each AI writer's identity, allowed trees and trust level.
- Every registry has a schema, and a Law fails any hand edit to a generated file.

## 5. Laws: every pub4 Law, stricter, proven

Rules and Laws are the same thing. All of pub4 MASTER's Laws carry over: their laws.yml statements and catalogue entries and their Ruby (`Law.define`, detectors, fixtures). pub4's checks, ratchets and house lint become kinds of Law in the same engine (`check`, `ratchet`, `lint`). The operator's directives (pub4's project_context.yml `operator_*` entries) and the agent rules are Laws too, of kind `conduct`, not a separate rules file.

A Law has: id, statement, kind (lexical, structural, rendered, runtime, ratchet, check, lint, semantic or conduct), detector, at least one bad and one good fixture, a proof test, severity, autofix policy and an enactment date.

**Policy and Ruby.** A Law's policy (statement, kind, severity, lifecycle, autofix, enactment date, census) lives only in its row in registry/laws.yml; its Ruby in laws/ holds the detector and fixtures. The engine accepts every word of pub4's `Law::Builder` DSL, so a pub4 Law body imports unchanged and its catalogue policy moves into the row.

**Lifecycle.**
1. Every Law, imported or new, enters as `advisory`.
2. It becomes `enforced` only when its fixtures prove at load, a census over the real tree shows a false-positive rate of 5% or less on a sample (sampled human or independent-model agreement), and the operator ratifies it. The engine refuses an enforced row that lacks any of these.
3. A Law may be judged by a model (`ask`) only if it has a rubric and a measured agreement rate of at least 80%. Otherwise it stays advisory forever.

**Bulk changes.** Any Law whose autofix would touch more than 20 files must publish a dry-run census first. This is the ASCII_PUNCTUATION lesson. Laws never rewrite text written before their enactment date.

**Import, then promote.** P2 imports all of pub4's Laws (520 catalogue entries, 514 `Law.define`) mechanically, plus the directives and agent rules as `conduct` Laws. A `conduct` Law with no detector stays advisory; it is still shown to every writer. Enforced Laws grow by promotion, one census at a time. Every finding names its Law and the measurement behind it. A census Law enforces one implementation per operation.

## 6. /fix from day one

1. **Protected paths.** Trusted main-tier writers may change source, tests, registries and entrypoints. Core protects production credentials, environment secrets, production runtime config, database migrations/schemas and the append-only ledger. Every main push passes bin/check and is judged by the gatekeeper.
2. **Lane cool-off.** One LaneState registry holds a handshake budget, a read-idle budget, a 30s→1m→5m→15m ladder and a circuit breaker per lane. There is one copy of this code.
3. **Commit messages.** Generated from the finding and the measured before/after delta, in commit_format. Trailers: `Law:`, `Measured:`, `Writer:`, `Proof:`. One repair per commit, scoped to paths.
4. **Rollback of refused repairs.** Each repair runs in a transaction: snapshot the touched bytes, run the parse, test, Law and visual gates. Any refusal restores the exact bytes and appends to fix_refusals.jsonl. Partial commits never happen.
5. **Token accounting.** Every model call goes through the core client, which writes tokens and cost to the ledger. Each run has a budget. The report shows tokens per landed fix and per refusal.
6. **Ratchet speed.** Ratchets are cached by a hash of the tree's contents and run incrementally on changed files. Budget: a full MASTER pass under 60s on the laptop; measure and record it.
7. **Visual lane.** Capture at 390, 360 and 320 px first; desktop only after all mobile captures, and desktop is what gets dropped when a pass is capped. Each pass renders a bounded share of surfaces. Checks are perceptual pixel diff, a computed-value audit against tokens, axe, and an independent reviewer that is a different model from the author. Every fixed defect gets a guard.
8. **Simplify stage.** It may only remove or merge, and some count must fall (selectors, distinct values, DOM depth, SCSS lines). It shows no visible change, or a change toward the Laws, and each count becomes a ratchet.
9. **Other writers.** Preflight considers only the paths /fix itself touches. There is one /fix lock per tree.

## 7. Migrating data and users from vm23

1. **Inventory.** List every `storage/production_*.sqlite3`, plus row counts per table, Active Storage blob counts and bytes, and a SHA-256 manifest.
2. **Rehearse.** On the rehearsal VM, restore from Litestream or offsite backup, run the pub5 migrations, compare row counts and checksums table by table, and run a smoke test as real users (log in, post, message, upload).
3. **Cutover per app.**
   - relayd serves a maintenance page and pub4 writes freeze.
   - Run `sqlite3 .backup` into a snapshot that is kept read-only.
   - Run the migration, verify it and run the smoke test.
   - Point relayd at pub5. Keep `secret_key_base` and password digests so sessions survive.
   - Copy uploads with the hash manifest.
4. **Rollback.**
   - Point relayd back and restart pub4 against the snapshot.
   - Writes made on pub5 come back through a reverse export script, kept for 7 days.
   - Rehearse the rollback before every cutover.

## 8. Deployment on the 1 GB VM

**Memory budget** (to be measured; RSS ceilings enforced by the resource guard):
- base OS and relayd about 150 MB
- master about 150 MB
- brgen family, one Falcon worker, about 250 MB
- amber about 150 MB
- bsdports about 120 MB
- Solid Queue runs inside each process
- Steady state stays under 85% of RAM (the current rule).

**Strangling by replacement.** pub4 and pub5 never run the same app at the same time on vm23. At each cutover the pub4 process stops when the pub5 process starts. Deploys go out only from a SHA that is green in CI and has passed `rehearse`.

## 9. Constraining multiple AI writers

- **Parse gate.** Installed automatically by `bin/setup`, not opt-in. It runs `ruby -c`, YAML and JSON parsing, and ERB compiling.
- **commit-msg hook.** Requires a `Writer:` trailer that matches writers.yml.
- **CI.** GitHub Actions on every push runs parse, unit tests for the touched trees and Laws on the diff. A red main blocks deploys and /fix.
- **Trust tiers.**
  - The operator and gated Claude push to main.
  - ChatGPT is explicitly trusted on main for `laws/**` and `registry/laws.yml` remediation, with every commit gated by `bin/check`.
  - GLM, Fable, Grok and Z.ai push to `inbox/<writer>`. The inbox merges only if `bin/check` is green, a reviewer model different from the author agrees, and the writer's allowed trees cover the change.
- **Scorecard.** Each writer's record (red CI, reverts, tests run) decides its tier, and the tier changes from those numbers, not from what the writer reports about itself.

## 10. Strangler versus big-bang

**Strangler (recommended).** Each step is reversible by putting the old relayd route back. Risk stays limited to one app at a time, and every phase produces real measurements. The cost is running two codebases for a while, plus the inventory and relayd glue.

**Big-bang.** One cutover, but the user data has a single copy, there is no CI and parse breaks are frequent. A failed cutover would take down every domain at once. Rejected.

## 11. Milestones

| Milestone | Exit criteria |
|---|---|
| M0 Freeze and measure | Every production DB restored on a second host, with integrity_check ok and counts and hashes equal; full pub4 suite measured; pub4 frozen for features |
| M1 Kernel | Core ≤5k lines; CI green; 40 or fewer knobs; one implementation per operation proven by the census Law; capability refusal test for each verb |
| M2 Laws and /fix | Every pub4 Law imported as advisory (statements, catalogue entries, `Law.define` Ruby), with checks, ratchets and house lint as kinds of Law and the operator directives and agent rules as `conduct` Laws; Laws promoted to enforced only by fixtures proved at load plus a census with false-positive rate ≤5% and ratification; /fix ran 7 days on pub5 with 0 red main and 0 unrolled-back refusals; tokens accounted |
| M3 bsdports live | 7 days on pub5 within its RSS budget; 5xx at or below pub4's baseline; rollback rehearsed |
| M4 brgen and engines live | Row and blob parity 100%; 7-day reverse export unused or exercised once; mobile visual lane green at 390, 360 and 320 px |
| M5 amber, mrdamascy, MASTER face, STUDIO live | Same as M3, plus dilla output matches pub4 byte for byte on fixtures |
| M6 pub4 archived | 30 days with no rollback; pub4 repo read-only |

## 12. Risks and how each is measured

| Risk | Measure |
|---|---|
| Data loss | Row counts and hash parity per table; restore drill every week |
| Memory over budget | RSS per process from the resource guard; free memory below 8% triggers an alert |
| Laws churning the repo | Files touched per Law autofix; the more-than-20-files rule |
| Writers breaking main | Red-main minutes per week; parse breaks per week (today: 84 in 14 days) |
| Rewrite stalls | Milestone dates against the exit criteria; pub4 production fixes counted separately |
| Registry drift | Hand edits to generated files (a Law); differences between registry and box from `rehearse` |
| Token cost | Ledger tokens per landed fix |
| Design regressions | Perceptual diff boxes and computed-value audit failures per pass |

## 13. Decisions for the operator

The same ten questions as in the summary, with options and recommended defaults:
1. Repo shape. Options: new repo, pub5/ inside pub4, or a branch. **Default: new repo.**
2. Migration approach. Options: strangler or big-bang. **Default: strangler.**
3. Writing to main. Options: everyone pushes to main behind the gate, or inbox branches for lower-trust writers. **Default: tiers as in §9.**
4. Process layout. Options: one process per app, brgen family plus the rest, or one process for every host. **Default: brgen family together, others separate.**
5. Rehearsal VM. Options: yes, temporarily, or no. **Default: yes, temporary.**
6. Session continuity at cutover. Options: keep secrets so users stay logged in, or force re-login. **Default: keep.**
7. Writes made on pub5 if we roll back. Options: reverse export or accept the loss. **Default: reverse export for 7 days.**
8. Rails version. Options: the pinned 8.2.0.alpha edge SHA or the latest stable 8.x. **Default: stable.**
9. MASTER web face. Options: Rails or Roda+Sequel. **Default: Roda+Sequel.**
10. Python. Options: remove it from the spine or keep it as an optional tool. **Default: remove.**

Also open, smaller: the knob budget (40).

### Critical files for implementation
- /Users/mac/Documents/GitHub/pub4/MASTER/data/laws.yml
- /Users/mac/Documents/GitHub/pub4/MASTER/data/project_context.yml
- /Users/mac/Documents/GitHub/pub4/RAILS/apps.yml
- /Users/mac/Documents/GitHub/pub4/OPENBSD/vm_resource.yml
- /Users/mac/Documents/GitHub/pub4/MASTER/data/tokens.yml
## 14. Decisions taken (2026-11-06)

1. Repo: this repository, a fresh history reusing the name pub5 (the August 2026 attempt was overwritten); private.
2. Migration: big-bang cutover, chosen by the operator. Because of that, these are mandatory, not optional:
   verified restore of every production database and upload on a second host before any work that touches data;
   a full cutover rehearsal on a temporary second VM (migrate, smoke-test as real users, roll back) repeated until clean;
   pub4 kept installed and stopped beside pub5 for 30 days, rollback by restoring relayd routes and starting pub4 on the cutover snapshot;
   a reverse export of writes made on pub5 during the first 7 days;
   parity of every app's key journeys (sign-in, post, message, pay, upload) proven in rehearsal before the switch.
3. Writers: the operator, gated Claude and ChatGPT push to main behind bin/check; GLM, Fable, Grok and Z.ai push to inbox/<writer> branches merged only on green bin/check plus review by a different model. ChatGPT's main-lane scope covers the full repository; credentials, environment secrets and live production data remain protected.
4. MASTER's web face: Roda + Sequel.
5. Laws: rules and Laws are one thing; every pub4 Law carries over, enters as advisory and is promoted by census (section 5). Operator directives and agent rules are `conduct` Laws.
6. One entrypoint: `bin/master` for every surface, dispatching from registry/commands.yml (section 4).
7. Python: banned outright - no Python scripts in the tree and no python3 in new code (operator, 2026-11-07). The three contact-sheet helpers carried that morning are removed the same day; dilla's reference pipeline, whose analyzer was already dropped, waits for the operator's engine call.
Remaining decisions (process layout, rehearsal VM, session continuity, reverse export, Rails version) take the plan's defaults until the operator says otherwise.

## 15. Port phases, mapped from pub4's TODO (2026-11-06)

The port's working plan lives in pub4's TODO.md ("pub5 - a ported fresh
start") and pub5's TODO rows are done there first. This section maps each
phase to this plan's milestones and names the gate that closes it, so one
file says where the port is and what proves it moved.

- Phase 0 - contracts locked in pub4 (M0's measurement face). Rows: route
  contracts (done: pub4 a772e3470a, amber + brgen hosts in 14be56ec75,
  checked off), signed-in route contracts (instrument 997af4779c; record
  needs the triangle booted and a seeded demo user per app), golden
  screenshots (machinery exists: browser_diagnostics + approve_visual_baselines;
  widen from the pixel_snapshot opt-in set to every manifest route and
  dialog state at 390/768/1280 px), one proof fixture per Law generated
  from laws.yml (the raw bad/good examples live inside every Law.define;
  what is missing is the generator), data export/import round-trip per app
  schema (AccountExporter exists and is tested; no round-trip test feeds
  its CSV back, and brgen draws no export route), MASTER CLI command
  contract (two entrypoints: bin/master and bin/operator's 47 verbs), and
  the one acceptance command that runs all of it against a target repo or
  URL. Gate: the acceptance command green against pub4 at lock time.
- Phase 1 - skeleton (done: dbb7653. README, AGENTS.md, PLAN.md; one Ruby
  3.4.9 reconciled with vm23; bin/lint and bin/test refusing to run blind;
  commit-format hook proven refusing a malformed subject; generated output
  gitignored).
- Phase 2 - OPENBSD (M1's deploy face plus the rehearse half of M0/M3):
  one registry (registry/apps.yml) generates relayd, rc.d and pf; one Ruby
  deploy tool ships a Mac-built artifact; rehearse per section 7.2 before
  any cutover. Gate: the generated configs diff-checked against the
  production-proven relayd/pf/rc.d kept verbatim (section 3), and the
  artifact lands from a Mac run.
- Phase 3 - RAILS (M3, then M4, then M5's amber and mrdamascy): rails/
  holds the shared engine plus each app; per-app SCSS overrides become
  token-only; build order decided 2026-11-06 - brgen and its engines
  first, then amber, then bsdports, then mrdamascy. Gate per app: its
  recorded route contracts, signed-in
  contracts and golden screenshots pass against the ported app before it
  goes live (the app-by-app gate inside the decided big-bang data
  cutover, section 14.2).
- Phase 4 - STUDIO: dilla and postpro behind one CLI. Gate: dilla's output
  matches pub4 byte for byte on fixtures (M5).
- Phase 5 - MASTER last (M1 core, M2 laws and /fix): core/ under 5k lines
  with capability refusals proven per verb; laws/ re-qualified under
  section 5's lifecycle; /fix per section 6 from its first day; soul.yml
  and laws.yml move byte for byte. Gate: pub4 MASTER governs until this
  MASTER passes every Law fixture (M6: archive after 30 rollback-free
  days).

Cross-cutting, owned by no single phase: registry/ (one file per concern:
apps, laws, models, knobs, tokens, commands, paths, writers, backlog) lands
alongside M1; the M0 database restore and parity drill runs before any
work that touches data, as section 14.2 makes mandatory.

## 16. Tree layouts, chosen (2026-11-06)

TREE_LAYOUTS.md holds the considered set - 18 layouts across the five
trees, pros and cons grounded in pub4 at e42dc7006c. The per-tree choices
it lands on: MASTER is a kernel-plus-plugins face (`core/` under 5k lines,
plugins/ for fix/review/io/web) with law/, checks/, tools/ and data/
around it; RAILS is the shared engine plus each app with brgen's five
engines under `brgen/engines/`, built in the decided order brgen first,
then amber, bsdports, mrdamascy; OPENBSD is registry-generated configs
over verbatim proven fixtures; STUDIO is one `bin/studio` over engines
that move byte for byte where proven; BPLANS never becomes a tree - text
in the plan now, backlog.yml rows at Phase 5. registry/ sits at pub5's
top level, not under master/. Where this section and phase rows above
differ in build order, the decided order (brgen first, 2026-11-06) wins.

## 16. Retiring pub4 by freeze, and curating history at milestones (operator, 2026-11-06)

Freeze, then delete. A pub4 part is frozen once its pub5 replacement passes
its tests and its Laws are enforced in pub5: frozen means no new work in pub4,
a pointer to the pub5 location, and a pub4 Law that refuses edits there. pub4
is deleted as a whole only after the cutover's 30 days without a rollback,
because until then it runs production and is the rollback. Laws freeze first,
once promoted in pub5.

History is curated at milestones, not continuously. At each milestone (core,
/fix and CLI, each app, cutover) writers pause, `bin/master history` rebuilds
the milestone's commits as logical chunks in dependency order (scaffolding,
registries, Law engine, Laws, plugins, apps), each chunk passes bin/check on
its own, one force-push lands it, a tag marks it, and writers resume from the
tag. A conduct Law triggers the curation at each milestone. Shared history is
never rewritten between milestones, because several writers push concurrently.
The first curation point is when /fix and the CLI have landed.

## 17. Port status (2026-11-07)

Measured against pub4 `origin/main` at `ec05e5df1e` with a per-file content
and name comparison of every tree.

**Complete.** OPENBSD: all 287 files carried (280 verbatim, the rest adapted
by the port; nothing missing). RAILS: every behavioural file carried -
3,407 verbatim, the rest adapted or relocated (`__shared` to `shared/`, the
five brgen engines to `brgen/engines/`); the only tree-wide omissions are
`refinements.yml` and `TODO.md` prose, dropped by section 3. STUDIO: all
files carried except `dilla/reference_analyzer.py`, dropped by section 3.
MASTER: soul.yml byte for byte at `master/data/soul.yml`; the Law engine and
all 520 catalogue entries imported mechanically through `bin/master
port-laws` (876 files under `laws/pub4/`, 909 rows in `registry/laws.yml`);
the 254-file checks surface carried and adapted under `master/checks/`; the
lib, web, tools and plugins redesign continues under the section 4
architecture, whose pub4 counterparts (92,000 lib lines, the Rails web face,
per-tree tooling) are deliberately rebuilt smaller, not copied.

**Landed in this pass.** BPLANS content kept verbatim per section 3, now at
`bplans/` (40 files plus its README; the build tools' temporary output
default renamed to `pub5-good-BPLANS`); the 32 golden screenshots of every
app and engine, now at each app's and engine's `screenshots/` directory; and
`rails/visual_completion.yml`, the operator's bounded layout-campaign
authorization.

**Not carried, by decision.** pub4's `redeploy` wrapper: it execs
`MASTER/bin/operator vps deploy`, a command this repo has not ported yet;
it returns with the Phase 5 CLI rather than as a wrapper that cannot run.
Python is banned outright (operator, 2026-11-07; `SHELL_DISCIPLINE` in
registry/laws.yml already names python on its banned-tool list): the three
pyvips contact-sheet helpers that were carried that morning left the same
day, their job returns to the Ruby visual lane in `master/checks/`, and
`studio/test/dilla_test.rb`'s analyzer test - which invoked python3
against the dropped `reference_analyzer.py` and could never pass - is gone.
`dilla reference` itself still names python3: it probes yt-dlp and demucs
through python3 when their CLIs are absent and aborts on the dropped
analyzer, so the feature is inert; porting that analyzer to Ruby or dropping
the feature is the operator's engine call, since section 3 keeps dilla's
sound engine verbatim. pub4's
MASTER `test/`, `lib/`, `web/`, `tools/` and `plugins/` trees stay out under
the section 3 redesign list; `core/`, `master/` and `laws/` are their
successors, and copying 2,000 files the architecture replaces would break
the one-implementation census. MASTER/data's remaining runtime files wait
for the Phase 5 plugins that read them; the concern files the architecture
names (apps, models, tokens, laws, paths, writers, commands, knobs) already
live in `registry/`.
