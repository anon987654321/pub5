# PROGRESS (host-agent window 2026-11-13 ~01:29 UTC)
Task: /fix RAILS -> MASTER -> OPENBSD -> STUDIO -> BIZ via MASTER bin/master.
LLM lane: host-agent bridge (self-lane, disclosed; not independent validation).

## State this window (honest proof)
- Prior window container recycled before push; nothing landed from it.
- This window: self-contained job re-clones @ origin/main, then pushes rebuilt
  agent_work/setup.sh (was MISSING at HEAD despite older claim) + portable
  env.sh (stale /home/workspace path removed) + this PROGRESS update.
- After push, job runs setup.sh: RUNNING (not yet proven). bundle: NOT_RUN.
- /fix RAILS: NOT_RUN. Sandbox: 20s tool wall, short TTL, ~458M disk, git+python only.

## Recipe (proven prior windows)
1. GH_TOKEN=... bash agent_work/setup.sh  (idempotent; zstd bootstrap, ruby extract,
   lib fetch, wrappers, usr-merge, gem fetch, bundle install --local, frozen=true)
2. . agent_work/env.sh; cd MASTER; bundle check
3. nohup ruby bin/master '/fix RAILS' > fix_rails.log 2>&1 &
4. Poll fix_rails.log + agent_spool/req_*.txt -> write resp_*.txt (host-agent answers).
5. Check .master/fix_runs.json; then /fix MASTER, OPENBSD, STUDIO, BIZ.

## Known blockers / fixes
- bin/master boot re-runs bundler -> tty-command reinstall error: env.sh +
  bundle frozen true + BUNDLE_PATH=MASTER/vendor/bundle.
- Container TTL short: re-run setup.sh first thing each window; push frequently.
- git push may race other windows: fetch + rebase before push (never force).
