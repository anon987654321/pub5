# pub5 — remaining work

Port record: `MIGRATION.md`. Source: pub4@`d6fa34d7580214b80b588a08880d0f4439b37f41`
(the port cut at `3e70be37c8`, then caught up the five commits pub4
landed later the same day; see "Catch-up port" in `MIGRATION.md`).
Rule for the whole port: same behaviour, less code; new features wait.
A source change, authored test, passing test, full suite, rendered product and
live deployment are different claims. Use PASS, FAIL, INCONCLUSIVE, BLOCKED,
NOT_RUN, TIMEOUT or DELIVERY_FAILED truthfully. A missing or unrun measurement
is INCONCLUSIVE, never PASS.

## 1. Port acceptance — run the contract suites on pinned Ruby 4.0.5

The port environment had no Ruby toolchain, so every acceptance run below is
NOT_RUN. They are the proof that the port preserved behaviour; run them before
any app goes live from pub5.

- [ ] **MASTER.** Run the focused Law, Soul, configuration, registry,
  replay-reader, fix-loop oscillation, reachability, run-ledger, media and CLI
  regressions; then `MASTER_TEST_START_MARKERS=1 MASTER_TEST_JOBS=1
  MASTER_TEST_JOBS_PROGRESS_EVERY=25 rake test`, `MASTER_TEST_JOBS=3 rake
  test`, `rake audit` and `bin/check --profile=agent`. Inspect
  `.master/check/suite-report.json` for incomplete workers.
- [ ] **RAILS.** Run `ruby RAILS/test/run_all.rb`, every app's `bin/ci`, and
  `ruby MASTER/checks/runner.rb --all`. The engine move under
  `brgen/engines/` is the port's main structural claim: the engine-discovery
  globs (`EngineRoots`, `stimulus_wiring`, `engine_boundaries`,
  `dead_css_sweep`, `generate_route_manifest`, `payment_honesty`,
  `fast_stage`) and the test-scope globs (`Pub5TestScope`, `ci.rb`,
  `test_scope_parity_test`) were rewritten for it and must be proven by their
  tests.
- [ ] **OPENBSD.** Run `ruby OPENBSD/test/run_all.rb` and the runner tests
  (the hook tests now exercise the root `.githooks/`). On an actual OpenBSD
  host, `pfctl -nf /etc/pf.conf`.
- [ ] **STUDIO.** Run `cd STUDIO && rake check test` on pinned Ruby 4.0.5,
  and prove the new `STUDIO/bin/studio` dispatcher reaches both dilla and
  postpro.
- [ ] **Generated-output freshness.** Run `cd MASTER && rake
  docs:agent_contracts` and `rake lint:agent_contracts` to regenerate the
  root contract and pointers from the marked block (the port hand-wrote
  them); compare with the committed files. Run
  `ruby MASTER/lib/operator/self_findings.rb --ratchet` after the suites
  settle.

## 2. vm23 cutover (operator decisions, BLOCKED on live access)

- [ ] Clone pub5 to `/home/dev/pub5` on vm23; the deploy chain names that
  path and refuses until it exists.
- [ ] Decide the installed-state rename cutover: `pub4-admin` → `pub5-admin`,
  `pub4ci` group, `/var/log/pub4*` → `/var/log/pub5*`, `/var/db/pub4*` →
  `/var/db/pub5*`, tmux `pub4-deploy` → `pub5-deploy`, and the matching
  `newsyslog.conf`/`rc.d` edits. pub5 keeps the pub4-installed names until
  the operator runs the cutover; the renamed paths above are the ones the
  port could not rename safely from code alone.
- [ ] Decide `pub4-shared` → `pub5-shared` (gem name, gemspec, Gemfiles,
  lockfile PATH entries, resolved require paths) as a deliberate follow-up.

## 3. Budget convergence (from the port plan)

The port carried behaviour; the plan's "same behaviour, less code" budget is
not met yet. Per-tree counts at the port commit are in the delivery summary;
targets: MASTER 700–900, RAILS 1,800–2,200, OPENBSD 100–150, STUDIO 40–50.

- [ ] Phase 0 contract locking, unchanged from the pub4 plan: route contracts
  per app and route; signed-in route contracts with a seeded demo user;
  golden screenshots at 390/768/1280 px; one proof fixture per Law generated
  from `laws.yml`, runnable against either repo; data export/import
  round-trip per app schema; MASTER CLI command contract; one acceptance
  command that runs all of it against a target repo or URL.
- [ ] Only after the contracts are locked: consolidate per-tree file counts
  toward the budget by rebuilding smaller against the contracts. Never delete
  behaviour to hit a count.
