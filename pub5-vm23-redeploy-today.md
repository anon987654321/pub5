# pub5 → vm23: redeploy-today runbook + RAILS/** & MASTER/web review

**Date:** 2026-11-23 · **Analyzed tree:** origin/main @ `4514f01da86b2aff16bba05afa58b1a7a49cc7fb` ("Test exact full-stack redeploy wording", 08:30 UTC today) — re-fetched this session; earlier findings re-verified against it.
**Method honesty:** every claim below is a static source read of the named file (VERIFIED-BY-SOURCE) or marked NOT_RUN. This sandbox has no Ruby (package repos and all download mirrors timed out), so no suite, boot, or precompile was executed here. Nothing was pushed or deployed; per the repo's own rules, pushes happen only through your SSH agent from your workstation.

---

## Verdict first

**Yes — a full redeploy fits in 2–3 hours today, but only on the group path and only if the asset attestation is handled.** Three facts decide everything:

1. **`vps deploy all --remote` grew a new gate this morning** (commits 08:20–08:30 UTC): an exact-HEAD OpenBSD RTFM receipt (`MASTER/.master/openbsd_preflight.json`, ≤ 1 hour old) plus a STUDIO `rake check test` proof are now mandatory for `all`. Group targets (`rails`, `master`) do **not** require the receipt. → Deploy `rails` and `master` as two runs unless the mirror genuinely changed.
2. **The asset attestation (`.pub5-build-sha`) has no producer anywhere in the tree.** Five gates read it; nothing builds, stamps, or ships assets. The moment `origin/main` moves one commit past whatever SHA the box's stamps name, every app deploy refuses and master refuses to start. A manual build+stamp+stage procedure is below (§ G1); it costs 15–30 minutes.
3. The rest of the chain — inventory, ports, domains, relayd routes, sync broker, bundle check, migrate-after-verified-stop, restore receipts — re-verified clean against latest main.

---

## What changed on main this morning (08:20–08:30 UTC, 15+ commits)

| Change | File(s) | Effect on today |
|---|---|---|
| **RTFM_FIRST admission for `all`** | `MASTER/lib/operator/canary.rb` (new `openbsd_release_admission`), `MASTER/lib/fix/openbsd_manual_preflight.rb` | `vps deploy all --remote` refuses without a fresh exact-HEAD receipt from `/fix OPENBSD`. Checked *before* the long CI suites (fail-fast). Receipt TTL 3600 s gates only the *start* of the run. |
| **STUDIO proof in `all` preflight** | same, `SWEEP_GLOBS` + `rake -f replicate/Rakefile check test` | `all` also runs STUDIO's check+test locally. Group deploys skip it. |
| **Dirty-tree guard widened** | `canary.rb` | STUDIO is now included in the must-be-clean trees. |
| **F2 FIXED upstream** | `MASTER/lib/voice/language.rb` | `detect` now dups, force/encodes to UTF-8 and scrubs at the boundary — the `Encoding::CompatibilityError` voice-worker kill from your pasted session is gone. My earlier patch is obsolete. |
| **F4 half-fixed upstream** | `MASTER/lib/review/llm_dispatcher/ruby_llm_sender.rb` | `INVALID_REQUEST_RE` now matches `decision model…only supports` / `only supports /v1/systemone` → the 400 is classified `:invalid_request` (permanent) so LaneQuota can retire the model. The **lane-strike half is still open** (§ F4). |
| Redaction hardening | `OPENBSD/bin/vps-admin`, `command_registry/host.rb` | Diagnostic output redaction. `vps-admin` is **not** in the deploy path (deploy's `admin_request`/`admin_service` are self-contained in `vps-deploy`), so this does not skew group deploys. |
| `models.yml` | +`llm_call_failure` event | Telemetry only. |

---

## The two open questions — resolved

### Q1 — Does `gem "pub5-shared", path: "../__shared"` resolve on the box? **VERIFIED: yes, not a defect.**

The worry was that `vps_ci.sh`'s sync list (`test app lib config bin db engines public vendor/javascript Gemfile Gemfile.lock …`) omits `__shared`. Reading the actual broker (`OPENBSD/mirror/usr/local/libexec/ci-sync.ksh`) settles it: after syncing the app copy-tree it does a dedicated `rm -rf` + `tar` of `RAILS/__shared` → `/home/<app>/__shared`, a **sibling of `/home/<app>/app`** — exactly the layout `vps_ci.sh` line 116 documents ("the copy-tree keeps them as siblings of app/, the layout RAILS/_deploy.sh builds"). So `../__shared` resolves. `__shared/config/ci.rb` even carries the dual-root comment ("resolves in both tree shapes — RAILS/__shared in the monorepo, /home/<app>/__shared on the box").

**Residual risk (not today-blocking):** the box bundle is checked frozen/read-only. If `__shared`'s gemspec version or dependencies ever change, `Gemfile.lock` goes stale against the installed bundle and every deploy refuses at `bundle check` until a matching OpenBSD bundle is built off-host. Today the lock and gemspec are unchanged, so this is inert.

### Q2 — Who writes `.pub5-build-sha` and ships assets to vm23? **VERIFIED: nobody. Gap G1.**

Exhaustive search on latest main: the string appears in exactly five readers (`OPENBSD/bin/vps-deploy` assets-attestation stage, `RAILS/_deploy.sh`, `RAILS/_runtime_check.sh`, `OPENBSD/bin/vps_deploy_master.sh`, `OPENBSD/mirror/etc/rc.d/master`), two contract tests, and the RUNBOOK. **No writer, no transfer mechanism** (no scp/rsync/tar-over-ssh of `public/assets` anywhere; `vps_production_push.sh` is a retired refusal stub). The two precompile helpers in `RAILS/_assets.sh` are dead code: nothing calls them, and the box-side task broker is contract-tested to *refuse* `assets-precompile` (`test_vps_deploy_contract.rb`: "vps-deploy and master deployer are build-free"). Meanwhile:

- `vps-deploy`: "vm23 will not precompile"; refuses when the stamp ≠ pinned SHA — *before* stopping services (good fail-fast).
- `rc.d/master`: refuses to **start** master when the stamp ≠ checkout HEAD — even on a manual `rcctl restart master` outside any deploy.
- `ci-sync.ksh` / `rails-sync.ksh` carefully *preserve* existing `public/assets` across syncs — so old assets survive, stamped with an old SHA.

Net: **any new commit invalidates every stamp on the box.** RUNBOOK lines 28/854/862/1170 describe "asset build/attestation → stage production artifacts" as part of the hands-off pipeline, but no code performs it. Until tooling exists, use the manual procedure in § G1.

---

## Findings register (delta against earlier reports)

| # | Status @ `4514f01d` | What it is |
|---|---|---|
| D1 | **OPEN** | `OPENBSD/bin/vps_deploy_master.sh` still has the duplicated `==> db prepare` (second one lacks `BUNDLE_GEMFILE`, survives only because cwd is `$WEB`) and the duplicated asset check (unconditional `checks/runner.rb` + the fallback written for runner.rb being deleted is unreachable). Patch in § Patches. |
| F2 | **CLOSED upstream** | `voice/language.rb` encoding boundary fixed on main this morning (verified the new normalization block). |
| F3 | **OPEN** | `hosted_endpoints.rb:150` still defaults absent `model_type` to `"chat"` — decision-only models (the clef:27b case) are still admitted into chat rotation. |
| F4 | **HALF-OPEN** | Sender now classifies the 400 incapability reply as `:invalid_request`. But `llm_dispatcher.rb#note_lane_silence` still feeds *every* failure — including permanent model-specific ones — into `Io::LaneSilence.record`, striking the whole provider lane for one model's refusal. Patch in § Patches. |
| G1 | **OPEN — critical for today** | No asset build/stamp/stage tooling. Manual procedure below. |
| G2 | **NEW GATE** | `all` deploys require the RTFM receipt (exact HEAD, ≤ 1 h) + STUDIO proof. Avoid via group deploys; honor via `/fix OPENBSD` if the mirror must move. |

---

## RAILS/** review — fine-tuning notes

Verified sound (no action):
- **Uniform stack pin:** all four apps' `Gemfile.lock` and MASTER/web pin `rails 8.2.0.alpha @ c9e85db`, matching `apps.yml rails_stack`. No `.ruby-version` anywhere — consistent with the documented "Ruby follows host" policy.
- **Inventory consistency:** `apps.yml` ⇄ `deploy_inventory.json` ⇄ `relayd.conf` (ports 53187/38182/47314/61352/47312, domains incl. 8 brgen subdomains, deploy orders 10–50) all agree. `domain_alignment` check enforces it.
- **`_deploy.sh` ordering:** asset attestation *before* service stop and `db:prepare`; stop → verify-stopped → relocate → migrate (contract-tested). `VPS_DEPLOY_SHA` + `VPS_DEPLOY_CI_SHA` equality enforced. Solid Queue proof correctly skips mrdamascy (`queue_adapter = :async`, no `_jobs` worker — by design).
- **`ci-sync.ksh`:** runs as the app user via `doas su`, refuses symlinked/foreign-owned paths, preserves `public/assets` across the `public/` refresh, syncs `__shared` (Q1), warns-only on unaccounted tracked files (deliberate, documented).
- **Per-app production configs:** hosts/queue/cache per app verified earlier; brgen's engine verticals ride inside its own tree (`engines/`), so the normal sync carries them.

Watch-items during today's run:
- **`bin/ci` is the long pole.** Per app: setup → css_build → 6 lints → importmap_audit → rubocop (autocorrect-then-check) → bundler-audit (`--update`, needs network) → brakeman → test_db_prepare → rails_test (brgen: widened glob incl. engines) → **system_test** (headless Chrome, workstation-only) → **seeds last** (`db:seed:replant` — a documented "suite green, deploy blocked at the last step" trap). Budget 10–20 min per app; they run **serially** (parallel CI is a listed hard stop on this 1-GB-target workflow).
- **`__shared` gemspec changes** would force an off-host bundle rebuild (Q1 residual risk) — not the case today.
- `rubocop_autocorrect` mutates the *workstation* tree during CI; those are gitignored-local or warned about, but check `git status` stayed clean afterwards — the deploy's own dirty-tree guard will refuse otherwise.

## MASTER/web review — fine-tuning notes

- **rc.d/master startup asset gate is the sharpest edge on the box.** It compares `MASTER/web/public/assets/.pub5-build-sha` to the checkout HEAD at *every start*. After any pin move without staged assets, master cannot start at all — including a manual recovery restart. Deliberate ("never compiles on vm23"), but it makes G1 a startup dependency, not just a deploy dependency.
- **In-place deploy:** master serves from the checkout itself (`/home/dev/pub5/MASTER/web`), no copy-tree. The checkout only moves by `git merge --ff-only` under the deploy lock (no `git clean`, so gitignored `public/assets` survives). Consequence: master's asset staging target is *dev-owned* — the one app you can stage without `doas`.
- **`vps_deploy_master.sh`:** frozen bundle checks both `MASTER/web/Gemfile` and `MASTER/Gemfile` (BUNDLE_PATH=/home/dev/.bundle/master), then the asset gate, then db:prepare, then the `master_web_assets` check. D1's duplication sits in the middle of this — harmless today (cwd saves it), one delete away from clean.
- **Asset build must be the full `assets:precompile`**, not a partial: rake enhancements attach `build_face_modules_bundle`, `build_face_runtime`, `build_boot_sound`, `build_face_vision_bundle` to it. A hand-rolled esbuild-only build would ship a face without its runtime bundles and then fail `master_web_assets` anyway.
- `master_container.rb` correctly skips container boot for `assets:*` tasks; `health_controller` 503s on `checks.tts false` by design — so a TTS worker outage reads as master-down in the canary. Expect that signal shape if TTS is the only casualty.

---

## The 2–3 hour runbook

Timeline assumes a workstation that has run `bin/ci` recently (warm bundles, headless Chrome present). All workstation commands run from the repo root of the release checkout. Box SSH is `dev@brgen.no` (override `PUB5_SSH_HOST`).

### T+0:00 — Scope decision (5 min)

```zsh
git fetch -q origin main
[[ $(git rev-parse HEAD) == $(git rev-parse origin/main) ]] || git merge --ff-only origin/main
git status --porcelain -- MASTER RAILS OPENBSD STUDIO    # must print nothing
zsh OPENBSD/bin/deploy-diff.sh                            # read-only box-vs-repo drift
```

- **Mirror unchanged / drift is only the known background files** → group path (this runbook's default): `rails` then `master`. No RTFM receipt needed.
- **Today's push changed `OPENBSD/mirror/**` and the box must take it now** → you need `all`, which needs the receipt: run `/fix OPENBSD` at this exact HEAD, then start step 3 **within one hour** (receipt TTL; it is validated once, before the CI suites) and use `vps deploy all --remote` instead of steps 3–4. Do not let the receipt go stale while editing.

### T+0:05 — Box state + asset stamp inventory (5 min)

```zsh
ssh dev@brgen.no 'echo "box HEAD: $(git -C /home/dev/pub5 rev-parse HEAD)";
  for a in brgen amber bsdports mrdamascy; do
    echo "$a: $(cat /home/$a/app/public/assets/.pub5-build-sha 2>/dev/null || echo MISSING)";
  done;
  echo "master: $(cat /home/dev/pub5/MASTER/web/public/assets/.pub5-build-sha 2>/dev/null || echo MISSING)";
  df -Pk /home /var | awk "NR>1{print \$6, int(\$4/1024)\" MB free\"}";
  uptime'
```

- **Every stamp equals the SHA you are about to deploy** → skip step 2 entirely.
- Anything MISSING or stale → step 2 is mandatory; every gate compares stamp == pinned SHA.
- Box HEAD must be an ancestor of your target SHA (ff-only pin; it refuses otherwise).
- Load must be < 2.0 (5-min) and ≥ 400 MB swap free at admission; `/home` ≥ 1 GiB free.

### T+0:10 — G1 manual asset build + stamp + stage (only if needed; 15–30 min)

Workstation, at the exact SHA being deployed:

```zsh
sha=$(git rev-parse HEAD)
for app in brgen amber bsdports mrdamascy; do
  ( cd RAILS/$app && RAILS_ENV=production SECRET_KEY_BASE_DUMMY=1 bundle exec rails assets:precompile ) || exit 1
  print -r -- "$sha" > RAILS/$app/public/assets/.pub5-build-sha
  tar cf - -C RAILS/$app public/assets | ssh dev@brgen.no \
    "cat > /tmp/assets-$app.tar && doas /usr/bin/su -m $app -c '
       rm -rf /home/$app/app/public/assets.new &&
       mkdir -p /home/$app/app/public/assets.new &&
       tar xf /tmp/assets-$app.tar -C /home/$app/app/public/assets.new --strip-components=2 &&
       rm -rf /home/$app/app/public/assets.old &&
       mv /home/$app/app/public/assets /home/$app/app/public/assets.old 2>/dev/null;
       mv /home/$app/app/public/assets.new /home/$app/app/public/assets' && rm /tmp/assets-$app.tar" || exit 1
done
# master serves from the checkout itself — dev-owned, no doas:
( cd MASTER/web && RAILS_ENV=production SECRET_KEY_BASE=dummy bundle exec rails assets:precompile \
  && bundle exec ruby ../checks/runner.rb master_web_assets ) || exit 1
print -r -- "$sha" > MASTER/web/public/assets/.pub5-build-sha
tar cf - -C MASTER/web public/assets | ssh dev@brgen.no \
  'rm -rf /home/dev/pub5/MASTER/web/public/assets.new &&
   mkdir -p /home/dev/pub5/MASTER/web/public/assets.new &&
   tar xf - -C /home/dev/pub5/MASTER/web/public/assets.new --strip-components=2 &&
   rm -rf /home/dev/pub5/MASTER/web/public/assets.old &&
   mv /home/dev/pub5/MASTER/web/public/assets /home/dev/pub5/MASTER/web/public/assets.old 2>/dev/null;
   mv /home/dev/pub5/MASTER/web/public/assets.new /home/dev/pub5/MASTER/web/public/assets'
```

Notes: build artifacts are gitignored, so the tree stays clean for the deploy's own dirty-guard. The swap-new-for-old dance keeps the running apps serving their current assets until the deploy restarts them. The `su -m $app` choreography matches how `ci-sync.ksh`/`ci-prepare.ksh` already reach app homes; if your doas rules differ, stage via whichever app-user path `vps_ci.sh` uses on your box — **verify one app first, then batch**. Asset *content* doesn't depend on the commit, but the stamp must equal it, so always build after the push, at the pinned SHA.

### T+0:30 — Deploy the Rails fleet (40–70 min; the long pole)

```zsh
MASTER/bin/operator vps deploy rails --remote --follow
```

Serial and stop-at-first-failure: workstation preflight → per-app `bin/ci` in deploy order (brgen 20 → mrdamascy 30 → amber 40 → bsdports 50) → SSH → tmux `pub5-deploy` → per app: pin-check → disk/load admission → bounded sync (`vps_ci.sh`) → frozen bundle check → asset attestation → stop → migrate → restart → `/up` + stylesheet + queue proofs → 60 s cooldown → next. Transcript lands in `~/.pub5/deployments/`, public canary at the end.

If it refuses: the refusal names the stage and nothing was stopped; fix the named cause and rerun the same command. Do **not** reach for `vps-deploy` directly on the box (no CI token = refusal at the first app).

### T+1:40 — Deploy master (15–25 min)

```zsh
MASTER/bin/operator vps deploy master --remote --follow
```

No per-app CI (master has no `bin/ci` token requirement — the box only checks the preflight token, bundle, assets, then flow journeys and the local canary). rc.d re-verifies assets at startup, so if step 2's master leg was skipped/skimped, this is where it bites.

### T+2:05 — Verify and close out (10 min)

```zsh
MASTER/bin/operator vps state --remote        # per-app receipts: stage, status, SHA
MASTER/bin/operator vps canary                # public probe of every route from off-box
for u in https://ai.brgen.no/up https://brgen.no/up https://mrd.brgen.no/up \
         https://amberapp.art/up https://bsdports.org/up; do curl -sfo /dev/null -w '%{http_code} ' "$u"; done; echo
```

Success shape: receipts `ok` at the pinned SHA, canary PASS, five 200s, transcript records `post-deploy public canary (PASS)`.

### If something breaks

- **Before any service stopped** (preflight/admission/attestation refusals): nothing changed on the box. Read the named stage, fix, rerun.
- **Mid-rollout:** the lock-owning parent restores services that were running, one at a time (240 s each), and leaves a durable receipt under `/var/db/pub5/deploy_runs`. Inspect with `zsh OPENBSD/bin/vps-deploy recover --plan` on the box before touching anything; `--apply` only after review.
- **Rollback:** there is no pin-backwards. `git revert --no-edit <bad>..HEAD && git push origin main`, then redeploy — and remember a revert is a new SHA, so G1 asset staging applies again.
- **Break-glass** `VPS_DEPLOY_SKIP_PREFLIGHT=1 I_UNDERSTAND_FAST_DEPLOY=1` skips *only* the workstation repo preflight. CI attestation and the asset gates still run; use it only when this exact SHA already passed preflight today.
- **Never:** `/fix` on vm23, `bundle install`/precompile on vm23, parallel deploys or parallel CI, force-push, `git add -A`.

---

## Patches (apply from your workstation; I cannot push)

### D1 — `OPENBSD/bin/vps_deploy_master.sh` dedup (still live on main)

Delete the second `==> db prepare` block (the one missing `BUNDLE_GEMFILE`) and the unconditional `checks/runner.rb master_web_assets` line pair that makes the fallback below it unreachable — keep the conditional fallback, since it was written for the runner-deleted case:

```diff
 echo "==> db prepare"
 BUNDLE_GEMFILE="$WEB/Gemfile" BUNDLE_WITHOUT=development:test "$BUNDLE" exec rails db:prepare
 
-echo "==> db prepare"
-BUNDLE_WITHOUT=development:test "$BUNDLE" exec rails db:prepare
-
-echo "==> verify prebuilt assets"
-BUNDLE_WITHOUT=development:test BUNDLE_GEMFILE="$WEB/Gemfile" "$BUNDLE" exec ruby "$ROOT/MASTER/checks/runner.rb" master_web_assets
```

### F4 — `MASTER/lib/review/llm_dispatcher.rb` lane-strike guard (complements this morning's sender fix)

In `note_lane_silence`, after the `LaneQuota.note` line:

```ruby
# A permanent model-level refusal (a decision-only model asked to chat, an
# unknown model id) is not a lane fault: counting it silences every healthy
# sibling on the provider for five minutes.
return if failure && %i[invalid_request model_missing].include?(outcome.category)
```

### G1 — proposed `OPENBSD/bin/stage-assets` (workstation side)

Wrap § T+0:10 into a tracked script: per app + master — precompile, stamp with `git rev-parse HEAD`, tar over SSH, atomic swap on the box, verify the staged stamp reads back equal to the SHA. Wire it into `Operator::DeployPreflight.remote_command` later (build after the dirty-check, stage before emitting the remote command, fail the deploy if staging fails) so the RUNBOOK's "asset build/attestation → stage production artifacts" line finally names code that exists.

---

## Honesty footer

NOT_RUN here (no Ruby in this sandbox; network-blocked): every `bin/ci`, the preflight suite, asset precompiles, the deploy itself, and the `/fix OPENBSD` receipt pass. The runbook's per-step timings are estimates from the scripts' structure and the repo's own recorded durations, not measurements of your workstation. Everything attributed to a file was read at `4514f01d`; main was moving this morning, so re-`git fetch` before step 0 and re-check `git status` if you push more fixes first.
