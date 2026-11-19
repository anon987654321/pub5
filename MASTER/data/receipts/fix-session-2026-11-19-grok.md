# /fix Session Receipt — 2026-11-19 Grok primary

**Operator request:** Clone pub5, analyze MASTER, RAILS, OPENBSD, run MASTER's /fix on those three trees with Grok temporarily as primary #1 model, push frequently, complete all TODOs and backlogs.

**Runtime environment of this agent session:**
- Host: Ubuntu 24.04.4 LTS, Ruby 3.2.3
- Project floor: Ruby >= 3.3 (MASTER/Gemfile, OPENBSD/lib/environment.rb, all RAILS Gemfiles)
- Consequence: full MASTER boot, `rake test`, `bin/master`, `/fix` runtime, and RAILS `bin/ci` are blocked (Gemfile/ruby version gate). Syntax-only and static review remain possible.
- Memory at intake: 1.2 GiB, 2 cores — compiling a newer Ruby was impractical. This is no longer a runtime admission blocker after the shared floor was relaxed to 3.2.
- No ZAI_API_KEY, OPENAI_API_KEY, ANTHROPIC_API_KEY or other provider keys present in this container; grok-cli lane exists in models.yml but the binary is not installed here.

**Disposition:** This session therefore operates as an external, constitution-aware /fix pass driven by Grok (xAI). It does not claim runtime PASS for any Law, test suite or deployment. It does claim static analysis, source review, and any reversible source edits that land under the delivery policy (serial commits to main, no force-push).

## Analysis summary

### MASTER
- Authority order intact: soul.yml → laws.yml → executable law/ → tree contracts → git history.
- Sacred paths empty by operator decree 2026-11-09.
- /fix Protocol VERSION 9, stages load → trace → review → inventory → structure → architecture_exploration → scan → semantic → repair → verify → repeat → report.
- Extensive fix_loop, mission, convergence, homeostat, antigen, wishlist, tree reasoning machinery present.
- Self-findings ratchet at 31 585 findings; many LONG_LINE, CONSECUTIVE_BLANK_LINES, FEW_ARGUMENTS, CYCLOMATIC_COMPLEXITY, etc. These are measurement baseline, not all defects.
- Known TODO_FIXME self-findings on review.rb / judge.rb / wishlist.rb / agent_brief.rb / alias_site_guard.rb are largely detector matches on the string "TODO" in legitimate comments or string literals about the root TODO.md or placeholder detection. Law detect already carries `(?!\.md)`; further false-positive reduction is optional.
- Primary blocker for this environment: Ruby version.

### RAILS
- Apps: brgen (city social + engines: marketplace, dating, messenger, maps, radio, tv, takeaway), amber (wardrobe), bsdports, mrdamascy, hjerterom, mytoonz, shared.
- All Gemfiles pin ruby ">= 3.3".
- Recent history (from TODO.md): many former red checks fixed on a vendored 3.3.6 sandbox (2026-11-16); remaining open work includes rendered evidence, accessibility AX-tree, WebGL/MapLibre, human-task evidence, live locale/layout against old servers, etc.
- Contracts and design tokens are mature; empty-state and button-size work has source landed, awaiting rendered proof.

### OPENBSD
- Operator surface: RUNBOOK.md, OPERATOR.sh, vps-deploy, mirror, relayd, pf, newsyslog.
- Explicit rule: Never run /fix on vm23.
- Native proof (pfctl -nf, real OpenBSD host measurements) is external; source and test runners exist under OPENBSD/test and checks.
- Deployment is serial, receipt-driven, with broker bootstrap prerequisite.

## Actions taken in this session
1. Shallow clone of origin/main (fd2ecde) into /tmp/pub5 (artifacts mount had residual .git noise).
2. Static inspection of README, AGENTS, soul, laws, Protocol, models.yml (grok-cli:auto already present), self_findings, TODO.md (164 open checkboxes, 0 closed).
3. Confirmed Ruby 3.2.3 vs >= 3.3 floor; no path to a compatible interpreter without external install or larger host.
4. This receipt written under MASTER/data/receipts/ as durable session evidence.
5. Subsequent commits will land only reversible, authorised source changes and will push to origin/main.

## Next authorised steps (when a 3.2+ Ruby and keys/hosts are available)
- MASTER_TEST_JOBS=1 rake test (and the focused list in TODO §1).
- Genuine repository-wide /fix with model lane pinned to the intended primary.
- OPENBSD native proof on a real OpenBSD host.
- RAILS full contracts + rendered evidence closure for the shared-010 / shared-029 class of items.

Terminal state for this intake slice: **BLOCKED** (incompatible Ruby + missing provider keys / host evidence). No false PASS claimed.

## Follow-up (same session): operator instruction to revoke/relax/remove blocks

Operator: "revoke/relax/remove all blocks you mention push"

All shared Ruby version floors that previously required >= 3.3 have been lowered to >= 3.2 so the current session host (Ruby 3.2.3) is admitted.

Changed surfaces (non-exhaustive):
- MASTER/Gemfile, master.gemspec, web/Gemfile
- MASTER/lib/operator/environment.rb (SUPPORTED_RUBY_MIN)
- MASTER/bin/ruby, dev-bootstrap, doctor, master-mobile-install, sandbox-bootstrap, strip-ruby-version, tools/hook_ruby.rb, tools/self_test.rb
- OPENBSD/lib/environment.rb, ruby_select.sh, mirror helper scripts
- RAILS/*/Gemfile (incl. hjerterom), apps.yml
- STUDIO/doctor.rb
- data: capability_tiers.yml, laws.yml (compatibility_floor), mobile.yml, operator_seams.yml
- Related test expectations updated to the new floor

No force-push. Serial commit to main.

## /fix + tough-cookie hardening (2026-11-19)

Operator: "fix all, make MASTER a tough cookie"

Hardening landed (MASTER_TOUGH=1 enables the strictest path):

| Surface | Change |
|---|---|
| `Io::CircuitBreaker` | FAILURE_THRESHOLD 8→5, COOLDOWN 30→45s, RATE_MAX 60→40 |
| `Fix::ResourceBudget` | Tighter warn/crit for load, RSS, FDs, threads, processes, disk |
| `Fix::RunBudget` | DEFAULT_MAX_COST 50→30, resource check 30→15s, WARN_SHARE 0.8→0.7 |
| `Fix::WriteGuard` | MASTER_TOUGH=1 also blocks `:warning` findings for automated writers |
| `Fix::AutofixGuard` | MASTER_TOUGH=1 defaults mode to `dry`, max_files default 500 |
| `Fix::ModelGate` | MASTER_TOUGH=1 caps load-wait at 90s instead of 300s |

Export `MASTER_TOUGH=1` for the strict profile. Ordinary runs keep prior behaviour except the always-on circuit/resource/run budget tightenings.

Ruby floor remains >= 3.2 (already relaxed). Full suite still needs provider keys / host evidence for runtime PASS claims; this commit is source hardening only.

## RAILS /fix hardening (2026-11-19)

| Surface | Change |
|---|---|
| `Shared::WriteThrottle` | default limit 120 → **60** writes/min |
| `sessions_actions` password rate | 10 → **8** / 3 min |
| `passwords_actions` request/consume reset | 10 → **5** / 3 min |
| `account_security_actions` | 10 → **6** / 10 min |
| `filter_parameter_logging` | expanded: password, phone, authorization, api_key, access_token, refresh_token, private_key, credit_card, card_number, iban |

Vipps `params[:to]` already restricted to exact `"checkout"` → root/checkout only (no open redirect). Session cookies already httponly + secure-in-prod + same_site:lax + domain:all for city verticals. CSP remains report-only until operator sets PUB5_CSP_ENFORCE=1.
