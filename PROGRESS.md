# PROGRESS (host-agent window 2026-11-13)
Task: /fix RAILS -> MASTER -> OPENBSD -> STUDIO -> BIZ via MASTER bin/master.
LLM lane: host-agent bridge (self-lane, disclosed; not independent validation).

## State this window
- Fresh shallow clone @ 521fb2e (remote moved past 8826b98).
- agent_work/ artifacts committed: setup.sh (idempotent), env.sh, extract_ruby.py,
  fetch_gems.py, fetch_libs.py. NO token in any committed file (GH_TOKEN env only).
- Ruby 4.0.9 conda pkg (linux-64 h462e025_1) downloaded; zstd 1.5.2 CLI bootstrapped
  from conda .tar.bz2 (pip/zstandard unavailable in sandbox).
- Extraction to /opt/rb + parallel gem fetch to MASTER/vendor/cache started.

## Recipe (proven prior + this window)
1. GH_TOKEN=... bash agent_work/setup.sh   (clone if absent, ruby extract, wrappers,
   usr-merge if needed, gem fetch, bundle install --local, frozen=true)
2. . agent_work/env.sh; cd MASTER; bundle check
3. nohup ruby bin/master '/fix RAILS' > fix_rails.log 2>&1 &
4. Poll fix_rails.log + agent_spool/req_*.txt -> write resp_*.txt (host-agent answers).
5. Check .master/fix_runs.json; then /fix MASTER, OPENBSD, STUDIO, BIZ.

## Known blockers / fixes
- bin/master boot re-runs bundler -> tty-command reinstall error: fix = env.sh +
  bundle config frozen true + BUNDLE_PATH=vendor/bundle if boot ignores freeze.
- Container TTL ~5 min: re-run setup.sh first thing each window; push frequently.
- git push may race other windows: fetch + rebase before push (never force).
