# PROGRESS

Task: execute MASTER /fix serially over RAILS, MASTER, OPENBSD, STUDIO and BIZ.
Authority: root AGENTS.md, MASTER/data/soul.yml, MASTER/data/laws.yml, tree contracts.
Delivery state: PARTIAL. No /fix tree run is claimed complete.

## Verified changes

- `agent_work/setup.sh` now persists the bundle path in `MASTER/.bundle/config`
  before installing gems, then freezes the bundle. This matches
  `MASTER/lib/boot/dependency_manager.rb`: boot deliberately clears ambient
  `BUNDLE_PATH` and uses the configured deploy bundle only when the local
  config names an existing directory.
- Commit pushed to `main`: `cbea7113b81eee58ed412803d6b1682ff6e391ad`
  (`fix(agent-work): align bootstrap bundle path with MASTER boot`).

## Current execution evidence

- GitHub repository access: connected GitHub integration has read and push
  permission; the commit above is present on `main`.
- This execution container: Ruby 3.3.8; Node 22.16.0; Chromium at
  `/usr/bin/chromium`.
- Bundler executable: unavailable on PATH. The Bundler 2.5.22 gem is present,
  but that does not provide a runnable `bundle` command in this container.
- Shell network: `curl -I https://github.com/` fails with
  `Could not resolve host: github.com`; no checkout can be cloned and gems
  cannot be fetched from this container.
- The GitHub connector can read and write repository files, but it does not
  execute Ruby or run repository commands. No `bin/master`, bundle, browser,
  app CI or /fix run has been executed in this environment.

## /fix status by requested tree

| Tree | Status | Evidence |
|---|---|---|
| RAILS | NOT_RUN | No current-run /fix receipt, app CI, interaction campaign or rendered browser proof |
| MASTER | NOT_RUN | No current-run /fix receipt, self-test or MASTER test output |
| OPENBSD | NOT_RUN | No native OpenBSD host/manual/remote deployment proof |
| STUDIO | NOT_RUN | No media regeneration or reproducibility proof |
| BIZ | NOT_RUN | No document render/format comparison or required human/legal review |

No tree is GREEN or DONE. Missing or unrun evidence remains INCONCLUSIVE under
MASTER's truthful-status law.

## Model-lane reality

The live `MASTER/data/models.yml` does not contain a Qwen4 or host-agent CLI
lane. Its primary list begins with GLM-5.3 and the OpenHands sandbox gateway.
The current ChatGPT session cannot be invoked by `cli_sender.rb` as an
external executable, so a self-spool lane must not be represented as a live
provider or independent council reviewer. Do not add a fictitious Qwen lane.

## Next execution requirements

A shell attached to the checkout is required. On that host:

1. Run `bash agent_work/setup.sh`; it now writes the local bundle path before
   installing the locked dependencies.
2. Source `agent_work/env.sh`; from `MASTER/`, confirm `bundle check`.
3. Run `bin/master --self-test` and retain its JSON receipt.
4. Execute `bin/master '/fix RAILS'`; complete its model dispatch and all
   available tests, visual/browser and app proofs. Record unavailable surfaces
   explicitly rather than relaxing their proof status.
5. Only after RAILS reaches a truthful terminal state, execute
   `bin/master '/fix MASTER'`; continue serially with OPENBSD, STUDIO and BIZ.

Use path-scoped commits to `main`, never force-push, and update this ledger
with command output and exact commit SHAs after each verified slice. Credentials
must stay in the host environment and must not be committed.
