# Manual dry-run simulation — friction and brittleness, pub5@main

Date: 2026-11-23
Evidence: operator's pasted session (Mac14,2, Ruby 4.0.5, MASTER 1.0.3, boot #7013) plus a static walk of every step in the four paths below. No Ruby exists in this analysis environment: every step marked *verified* was confirmed by reading the source the step executes, not by running it. Runtime behavior is NOT_RUN and says so.

The two uploaded pastes are byte-identical copies of one session.

## Path A — cold boot

**What the operator typed:** `bin/master` at the repository root → `zsh: no such file or directory`. Then `chmod +x bin/master` → same failure. Then `cd MASTER && chmod +x bin/master && bin/master` → boots.

**Simulated trace:**

1. `bin/master` at repo root — **fails**. The repository has no root-level `bin/`; the one entrypoint is `MASTER/bin/master`. Verified: no `bin/` directory exists in the checkout.
2. `MASTER/bin/master` — resolves its own root from `__dir__`, so it works from any cwd. Verified.
3. Boot sequence runs deps check (`deps0`), RubyLLM model discovery, dmesg banner — 22.4 s boot on an M2. All observed lines match the boot sources. Verified by correspondence.

**Friction found:**

- **F1 — the first command a person types fails.** The docs say `MASTER/bin/master`, but `bin/master`'s own header comment calls itself "`bin/master`", and a human standing in `pub5/` naturally types `bin/master`. The fix is a two-line root shim, and this transcript is the justification the existing-first rule asks for:

```sh
# bin/master (new file, repo root, mode 755)
#!/bin/sh
# Convenience shim; MASTER/bin/master is the one entrypoint and resolves its own root.
exec "$(dirname "$0")/MASTER/bin/master" "$@"
```

## Path B — the chat deploy request

**What the operator typed:** "hi, can you please redeploy OPENBSD, RAILS, STUDIO, and MASTER/web on vm23? …"

**Simulated trace** (`MASTER/lib/cli/turn_router.rb` → `operator_intent.rb` → `command_registry/host.rb#dispatch_deploy`):

1. Not a /fix shape, not a shell paste, does not end with `?` — falls through to `OperatorIntent`. Verified against the routing order.
2. `non_deployable_tree_request?` does **not** fire: naming STUDIO would refuse the request, except `complete_stack_components?` (mentions both OPENBSD and RAILS) explicitly cancels that refusal. So STUDIO is silently dropped from scope rather than named as undeliverable. Verified.
3. `repository_wide_deployment?` → true; the bus shows `operator0: intent_resolved, target all` — matching the transcript.
4. `direct_full_stack_confirmation?` → true (polite prefix "hi, can you please" + "redeploy" + vm23 + full stack), so the router dispatches **`/deploy all --confirm` — the phrasing of a polite question is itself the production confirmation.** Verified in source. The transcript contains no deploy output and MASTER's reply text is not in the paste, so what the deploy did is INCONCLUSIVE — but the operator's follow-up ("so whats the deal you are unable to do as i asked?") says the reply did not read as "deployment running."

**Friction and brittleness found:**

- **F7 — polite question = production consent.** `can you please redeploy … ?` supplies `--confirm` with no second gate. This is deliberate (`direct_full_stack_confirmation?` exists for exactly this), but after this session the operator may want the full-stack path to answer with the plan and require a literal `--confirm`. Operator decision; flagged, not patched.
- **F8 — STUDIO vanishes from scope silently.** The reply the operator perceives should say "STUDIO is not deployable; deploying the five registered surfaces" — the code path that would say so (`non_deployable_tree_request?`) is disabled precisely when the request names the full stack. One-line behavioral note for whoever owns the adapter; the inventory answer is the truthful one.

## Path C — the voice crash and TTS cascade

**Transcript:** `queue0: worker failed - Encoding::CompatibilityError: incompatible encoding regexp match (UTF-8 regexp with BINARY (ASCII-8BIT) string) at voice/language.rb:42` → socket retry → one-shot worker → no audio → OS voice fallback.

**Root cause, verified in source:** `Master::Voice::Language.detect` does `body = text.to_s`, preserving encoding. Provider streams and sockets deliver ASCII-8BIT; the reply that turn came from `nvidia/nemotron-3-nano-omni-30b-a3b-reasoning` after the cascade — a streamed response, bytes in BINARY. Line 42 matches the UTF-8 `NORDIC_LETTERS` regexp against it → raise → worker dead → four fallback lines for one sentence. Nine call sites route through `detect`, so the boundary fix belongs there:

```ruby
# MASTER/lib/voice/language.rb
      def detect(text)
        body = detectable_body(text)
        return :nb if body.match?(NORDIC_LETTERS)
        return :ms if body.match?(MALAY_MARKER_RE)
        body.match?(MARKER_RE) ? :nb : :en
      end

      # Streams and sockets hand over ASCII-8BIT; a UTF-8 regexp against one
      # raises Encoding::CompatibilityError and kills the voice worker
      # (queue0, 2026-11-23). Force and scrub at this one boundary: real UTF-8
      # (æøå included) survives; stray bytes become U+FFFD and cannot match.
      def detectable_body(text)
        body = text.to_s
        return body if body.encoding == Encoding::UTF_8 && body.valid_encoding?

        body.dup.force_encoding(Encoding::UTF_8).scrub
      end
```

- **F5 — the one-shot worker's failure line is boot noise.** `tts-worker` re-execs with a clean env and runs `Boot::Entrypoint.prepare!`, whose `deps0` banner lands on the child's stderr — twice — inside the error the operator reads. The actual cause ("the Edge endpoint answered nothing") is the last clause. Direction, not a patch: `Entrypoint.prepare!` needs a quiet mode for worker children, or the failure renderer should strip `deps0:`-prefixed lines. The Edge endpoint itself being unreachable is external to the repo.

## Path D — the provider cascade

**Transcript:** replicate gpt-5.2 quota → ollama_cloud deepseek quota → claude-sonnet-5-5 quota → ollama_cloud beam quota → **ollama_cloud clef:27b hard 400 ("decision model, only supports /v1/systemone") → whole ollama_cloud lane silenced 5 min** → two gemma rate limits → nemotron answers (8th lane tried).

**Verified in source:**

1. **Discovery admitted a decision-only model to a chat lane.** `HostedEndpoints` filters discovery rows with `row.fetch("model_type", "chat") == "chat"` — a row *missing* the capability field defaults to chat. `clef` appears nowhere in the repo's static config; it arrived via live discovery. Verified.
2. **The 400 retires nothing.** `LaneReply.read` has verdicts for billing, spent/quota, 429, unreachable and auth — no pattern for a 400 incapability, so `LaneQuota.note` records nothing and clef:27b stays in rotation to fail again after the cooloff. Verified.
3. **The strike punishes the provider.** `note_lane_silence` feeds every failure — including a permanent, model-specific `:invalid_request` — into `LaneSilence.record`, whose three-strike rule silences the whole lane. clef's 400 was the third strike that sank ollama_cloud. Verified.

**Patch for (3)** — `:invalid_request` and `:model_missing` are permanent properties of one model, and must not count as lane strikes:

```ruby
# MASTER/lib/review/llm_dispatcher.rb, in note_lane_silence, after LaneQuota.note:
        # A permanent model-level refusal (a decision-only model asked to chat,
        # an unknown model id) is not a lane fault: counting it silences every
        # healthy sibling on the provider for five minutes, and the model stays
        # in the catalogue to fail again. ollama_cloud:clef:27b, 2026-11-23.
        return if failure && %i[invalid_request model_missing].include?(outcome.category)
```

**Follow-up, not patched:** model-scoped retirement. Today's stores are lane-scoped by design (`LaneQuota.note`, `drop_for_run!`, `LaneSilence`); nothing forgets one bad model. The transcript is the finding that justifies a per-model dead-list; the change wants its own contract decision, not a drive-by.

**Hardening to consider for (1):** treat absent `model_type` as unknown rather than chat, or re-check a discovered model after its first `:invalid_request`. Admitting unknown-by-default is what let clef in; rejecting unknown-by-default may exclude legitimate models from providers that do not annotate. Operator's call.

## Path E — `/fix` dry run, simulated step by step

`MASTER/bin/fix-here RAILS --dry` — every call the wrapper makes was resolved against the tree:

| Step | Resolves to | State |
|---|---|---|
| interpreter | `MASTER/bin/ruby` (host Ruby ≥ 3.2; Ruby 4.0.5 qualifies) | verified |
| tree validation | `MasterPaths::TREES` = MASTER RAILS OPENBSD STUDIO BIZ, or an existing path | verified |
| production guard | refuses on vm23 / `PUB5_PRODUCTION_HOST=1` | verified present |
| disk floor | `budgets.yml` → `process.resources.disk_free_gb.crit` = 1 GiB (no stale hardcoded 2.0) | verified |
| saved model | `.master/config.yml` fallback chain | verified |
| `--dry` exit | prints `would run MASTER/bin/master /fix RAILS`, exits 0 | verified |
| (wet runs only) state prep | `Fix::Kernel#lifecycle_journal.prepare_state!` — `kernel/lifecycle_journal.rb:123` | verified |
| (wet) parse preflight | `Operator::ParseSweep.failures/render` | verified |
| (wet) stall watch | `Operator::StallWatch.abort?/tail/limit`, `RunPlan.line` — both live in `stall_watch.rb` | verified |
| (wet) app lifecycle | `bin/operator triangle up/down` for rendered RAILS lanes; `Fix::ServerLeases.reap_orphans!` after | verified |
| (wet) publish | commits path-scoped; `--no-publish` holds them local | verified |

`/fix <target> --dry-run` inside the CLI: mode defaults to repair with `apply=false`; `RunBudget.with_shared_run(max_passes: 0)`; target resolution accepts any path in the five trees, tree lists, or `all`/`everything`. Provider policy (`LanePreflight`) refuses an all-free-lane run before budget is spent, and deliberately measures live availability *later* — a read-only preview with a dead fleet still does its scanner pass instead of dying. Good design; verified.

**Friction found:**

- **F6 — `--dry` is shallower than its banner.** `fix-here`'s header says "--dry only checks readiness", but it exits before the parse sweep and the lane probe run, so "ready" means tree/disk/model only. A broken-Ruby tree passes `--dry` and fails the real run seconds later. Either run the parse sweep under `--dry` (it is fast and read-only) or say "checks tree, disk and model" in the banner. Small patch, real time saved.

## Carried from the readiness review

- **D1 — `OPENBSD/bin/vps_deploy_master.sh` duplicated steps** (double `db:prepare`, double asset check; the unconditional `checks/runner.rb` call at line 138 defeats the fallback below it). Patch delivered in `pub5-master-readiness.md`. Still present in the tree this session ran from.
- **D2 — box config drift advisory-only**, last measured 2026-09-10 with eight drifts including `rc.d/master`. Re-measure on vm23.

## NOT_RUN (honest remainder)

No Ruby, no vm23 access, no provider credentials here. Before acting on any patch: `MASTER/bin/operator test MASTER/test` for the voice and dispatcher changes, `test_err_classification.rb` for the Result-category touch, then `bin/check --profile=ci`. The deploy chain itself remains verified-by-source only.
