# MASTER readiness review — vm23 deployment and /fix

Date: 2026-11-23
Source: `github.com/anon987654321/pub5` @ `main` (tarball snapshot, VERSION 1.0.3)
Method: full static read of the deploy and repair chains. This environment has no Ruby and no access to vm23, so every runtime claim is marked NOT_RUN where it could not be executed. Per MASTER's own epistemics, nothing here is reported as PASS that was not measured.

## 1. Governance acknowledged

MASTER is the primary configuration for every agent in pub5. The authority order stands as declared:

1. `MASTER/data/soul.yml` — identity, preservation, source precedence (v3.0.0, `sacred_paths: []` by operator decree 2026-11-09).
2. `MASTER/data/laws.yml` — the one Law catalogue: 346 statement rows plus `law_catalogue` with 560 executable entries (532 active, 16 trusted, 8 advisory, 4 retired; 103 error, 280 warning, 176 info, 1 veto; autofix: 79 automatic, 449 review, 32 never).
3. `MASTER/law/` (32 detector files) + `MASTER/checks/` — enforcement instruments.
4. Tree contracts (`MASTER/data/law/TREE_CONTRACTS.md`), then Git history as provenance only.

Integrity measured in this review:

- Every one of the 560 catalogue entries has a `definition_sources` file that exists in the checkout. **0 dangling references.**
- All core YAML parses clean: `laws.yml`, `soul.yml`, `RAILS/apps.yml`, `task_contract.yml`, `budgets.yml`, `vm_resource.yml`, `checks.yml`, `scan_coverage.yml`.
- All 34 `MASTER/bin/*` entrypoints carry the executable bit; every shebang file that is executed directly is executable. (`OPENBSD/bin/reach` has neither shebang nor exec bit by design — it is `load`ed; `OPENBSD/bin/domain_watch.rb` is invoked via `$RUBY`, so its missing bit is correct.)
- The deploy-path static guard from `OPENBSD/test/test_deploy_paths_exist.rb` was replicated here: 91 deploy scripts scanned, every `RAILS/`, `MASTER/`, `OPENBSD/`, `STUDIO/` path they name exists (one false positive: `MASTER/data/runtime` in `OPENBSD/bin/tree` is a prefix rule, not a file read).
- `OPENBSD/mirror/` children are exactly `etc home usr var`, matching the mirror contract test.

`ruby MASTER/tools/agent_context.rb --json`: **NOT_RUN** (no Ruby in this environment). The full MASTER suite, `LawRegistryAudit`, and the parse sweep: **NOT_RUN** for the same reason. These must run in the real checkout before any release claim.

## 2. Deploying all Rails apps and MASTER web to vm23

### The chain, as verified statically

One canonical entrypoint: `MASTER/bin/operator vps deploy <app|group|all> --remote`.

1. **Workstation side** (`Operator::DeployPreflight` in `MASTER/lib/operator/canary.rb`): repository preflight plus `bin/ci` for every selected Rails app, run serially against the exact SHA. Only on pass does it emit the attestation tokens (`VPS_DEPLOY_PREFLIGHT_SHA`, `VPS_DEPLOY_CI_SHA`) and pin `VPS_DEPLOY_SHA`. Break-glass (`VPS_DEPLOY_SKIP_PREFLIGHT=1`) requires the human-only `I_UNDERSTAND_FAST_DEPLOY=1`.
2. **Transport**: tmux session `pub5-deploy` on vm23; output collected to a workstation log; the box writes no transcripts, only structured recovery receipts in `/var/db/pub5`. A second concurrent top-level deploy is refused by the directory lock, whose owner record carries PID + hostname + epoch + process-identity (start time + command cksum), with a two-phase stale-lock reaper.
3. **On the box** (`OPENBSD/bin/vps-deploy`, root via doas with a prefix env allowlist, never keepenv): fetch + pin one SHA (non-fast-forward refused), host load admission (5-min load < 2.0, ≥ 400 MB free swap, CPU-pressure file honored), service snapshot before anything is touched, then serial per-app children in `apps.yml` `deploy_order` (master 10, brgen 20, mrdamascy 30, amber 40, bsdports 50) with 60 s cooldowns — correct for a 1 vCPU / 1 GiB host. `all` first applies the OpenBSD filesystem mirror via `OPERATOR.sh --apply`.
4. **Per Rails app**: copy-tree sync + read-only bundle verification (`vps_ci.sh`), prebuilt-asset attestation (`.pub5-build-sha` must equal the pinned SHA — host-side precompile is refused by design), stop → idempotent `db:prepare` (primary + secondary schemas) → restart → `/up` poll → linked-stylesheet 404 check (the 2026-08-14 lesson) → Solid Queue proof where a worker exists → restore shed services → check battery (`production port_inventory generated_asset schema_migration phantom_foreign_keys frontend_production stimulus_components flow_journey page_simulation`) → final `rcctl check` → local canary as a release gate → deploy stamp.
5. **MASTER web** (`OPENBSD/bin/vps_deploy_master.sh`): deploys in place at `/home/dev/pub5/MASTER/web` (never a copy-tree), verifies the inherited parent lock by process fingerprint, checks both frozen bundles, requires prebuilt assets attested to the pinned SHA, `db:prepare`, hardened runtime-dir creation, rc.d drift refusal, `rcctl restart master`, then `/up` plus a two-minute `/health` poll that reads the TTS socket state, and `probe_http`.
6. **Failure semantics**: every exit lands in `finish()` — stamps `failed`, names the stage, lists services left down with the exact recovery command; the lock owner restores the pre-deploy service set one at a time with `/up` waits. Interrupted runs leave durable receipts; `vps-deploy recover --plan|--apply <run-id>` restores only the recorded snapshot after liveness and ambiguity checks.

### Inventory consistency (measured)

| App | Port | Domain | deploy_script | rc.d mirror | relayd route | Jobs worker |
|---|---|---|---|---|---|---|
| master | 53187 | ai.brgen.no | `OPENBSD/bin/vps_deploy_master.sh` | yes | yes (SAN on brgen.no cert) | n/a |
| brgen | 38182 | brgen.no (+8 subdomains) | `RAILS/brgen/brgen.sh` | yes | yes | brgen_jobs |
| mrdamascy | 47314 | mrd.brgen.no | `RAILS/mrdamascy/mrdamascy.sh` | yes | yes | none — `:async` adapter, consistent with the deploy skipping its queue proof |
| amber | 61352 | amberapp.art | `RAILS/amber/amber.sh` | yes | yes | amber_jobs |
| bsdports | 47312 | bsdports.org | `RAILS/bsdports/bsdports.sh` | yes | yes | bsdports_jobs |

`OPENBSD/deploy_inventory.json` agrees with `RAILS/apps.yml` on name, port and domain for all five. `hjerterom` and `mytoonz` are restored source only and are correctly absent from the deploy inventory, relayd and rc.d — `apps.yml` documents exactly why they must stay out. `irc_gateway` has an rc.d entry outside the inventory; it is a manually managed service, referenced as such by `bin/reach`.

### Defects found

**D1 — `vps_deploy_master.sh` runs the database and asset steps twice, and the fallback that was the fix is unreachable in the failure it was written for.**
Lines 131–135 run `==> db prepare` twice back to back; the second call drops `BUNDLE_GEMFILE` and only works because the cwd happens to be `$WEB`. Then line 137–138 runs the `master_web_assets` check through `MASTER/checks/runner.rb` **unconditionally**, while lines 158–170 carry the conditional fallback added after runner.rb's 2026-09-16 deletion — the comment there describes the deploy dying under `set -e` when runner.rb was missing. As long as line 138 stands, that exact death recurs *before* the fallback is reached, and every master deploy pays a second Rails boot on a one-core box. Fix: delete lines 134–135 and 137–138, keeping the conditional block.

**D2 — config drift on the box is advisory and measured stale.**
`vps-deploy` warns on drift but only refuses under `VPS_DEPLOY_DRIFT=fail`. The in-script note records eight differing configs on 2026-09-10, one of them `rc.d/master`. That measurement is two months old; per the script's own comment, the warning should become blocking once the box runs clean. **INCONCLUSIVE** whether it ever has.

### Deliberate limits (not defects)

- No staging environment — a documented refusal; vm23 is the only environment.
- Browser checks (`rendered_suite layout_suite`) are opt-in via `PUB5_DEPLOY_BROWSER_CHECKS=1`, because Chrome on 1 GiB with the fleet up is what sheds amber and bsdports.
- `vps_production_push.sh` fast-push is retired and refuses to run. `RAILS/deploy.sh` is a compatibility shim that refuses root and delegates to `vps-deploy`.

## 3. Running /fix over literally anything

### What /fix is

`/fix [path]` is the one pipeline command (`MASTER/lib/cli/command_registry/review.rb` → `Master::Fix::FixLoop`, 160+ files under `MASTER/lib/fix/`). It observes, critiques, repairs, re-observes and proves, per pass, inside a shared `RunBudget`.

**Reach — measured against the code:**

- **Targets** (`Pipeline::TargetResolver`): any single path inside the five governed trees (`MASTER RAILS OPENBSD STUDIO BIZ` — `MasterPaths::TREES`), a comma/space list of trees as a queue, `RAILS/**`-style scope notation, `all`/`everything` for the whole checkout, or a bare `/fix` for MASTER itself. A word no tree owns is refused by name. `fix-here` independently validates the target exists.
- **Languages**: the catalogue declares detectors for ruby, html, css, scss, javascript, json, yaml, zsh and markdown; `universal_by_default: true` with `languages: []` on 276 entries means language-agnostic Laws apply to every artifact. Modalities: lexical, semantic, visual. Surfaces run from `lines` and `syntax_tree` to `rendered_ui`, `interactive_behavior`, `runtime` and `deployment`.
- **Documents plane**: BIZ (html/svg/pdf) is governed; DOCX/PDF/XLSX/PPTX changes stay INCONCLUSIVE until a format-aware source check and rendered-output comparison exist — a missing dimension is never a PASS.
- **Modes**: `repair` (default), `audit` (council critique, never mutates), `visual` (style-only read), `elevate`, `all`. Lanes: code/standard/visual/all, with `standard` auto-selected for rendered targets so the apps boot first.

**Consent gates — this is where "literally anything" ends, deliberately:**

- Bare `/fix` is a read-only preview. Mutation requires **explicit `--mode=repair|elevate|all` plus `--apply` plus a named repository target**; `--dry-run`/`--read-only` override `--apply`. An `--apply` with a stage-selected run and no explicit target is refused.
- `fix-here` refuses to run on vm23 itself (`PUB5_PRODUCTION_HOST` / OpenBSD + `/etc/master.env` heuristic) — production is never a repair target.
- `soul.yml` and `laws.yml` are operator-owned: /fix never edits them; a human commits validated changes.
- Startup, retry and autonomous triggers never imply consent; external actions and operator-only seams stay human-gated.

**Operational wrap (`MASTER/bin/fix-here`)**: disk floor read from `data/budgets.yml` (not a hardcoded number), repo-wide parse sweep before spending a model call, one bounded LanePreflight probe, per-tree followable log, stall watch (`MASTER_FIX_ABORT_S`), TERM→KILL escalation on the whole process group, RAILS triangle boot for rendered lanes, orphan-server reaping afterwards, and a post-run check that a zero-exit child actually wrote `fix0` lines.

**Proof discipline**: intent-scoped TaskContract (`data/task_contract.yml`), FixPlan evidence spine, RunJournal terminal evidence, Law × stream × surface receipts, `FinalCleanup` on every exit, commits path-scoped and pushed to `main` (or held with `--no-publish`).

### Gaps to know before relying on it

- **Provider dependency**: a real /fix run needs the model pool (HANDOFF.md pins `zai-cli:auto` for cron 541280). With no credentials, /fix can preview but council lanes cannot execute. **NOT_RUN** here.
- **`/fix all` breadth**: resolution to repo root is supported, but a whole-checkout mutating run is bounded by `RunBudget`/`ABSOLUTE_MAX_PASSES` and the disk/stall guards; it is a marathon with receipts, not a single sweep.
- The known-debt tag `agent-ignore` can fail `--profile=agent` checks unrelated to a given patch — expected, documented.

## 4. Verdict

- **Deploy to vm23: structurally ready.** One entrypoint, one pinned SHA, fail-closed admission, verified inventory/routing/rc.d coverage for all five active apps, honest failure semantics with receipts and recovery. One hygiene defect (D1) to repair in `vps_deploy_master.sh` and one staleness question (D2) to re-measure on the box. Neither blocks a deploy today; D1 re-opens a previously suffered outage mode the day `runner.rb` moves again.
- **/fix over anything: ready within its constitution.** Any path in the five trees is a legal target; nothing outside the trees, nothing on production, nothing without explicit `--mode` + `--apply` + named target, and soul/laws stay human-only. That is the design, not a limitation to work around.
- **Before the next release claim**, run in the real checkout: `ruby MASTER/tools/agent_context.rb --json`, `cd MASTER && MASTER_TEST_JOBS=1 bundle exec rake test`, `bin/check --profile=ci`, and — on vm23 — a fresh drift measurement. This review measured source; it did not execute the system.

## 5. Suggested patch for D1

```diff
--- a/OPENBSD/bin/vps_deploy_master.sh
+++ b/OPENBSD/bin/vps_deploy_master.sh
@@ echo "==> db prepare"
 BUNDLE_GEMFILE="$WEB/Gemfile" BUNDLE_WITHOUT=development:test "$BUNDLE" exec rails db:prepare
-
-echo "==> db prepare"
-BUNDLE_WITHOUT=development:test "$BUNDLE" exec rails db:prepare
-
-echo "==> verify prebuilt assets"
-BUNDLE_WITHOUT=development:test BUNDLE_GEMFILE="$WEB/Gemfile" "$BUNDLE" exec ruby "$ROOT/MASTER/checks/runner.rb" master_web_assets
```

(The surviving conditional block at the former lines 158–170 already performs the asset check through whichever door exists; keep it as the single invocation.)
