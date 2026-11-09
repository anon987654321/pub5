# Agent wish list

Provenance: written 2026-11-09 by the external agent that landed
expectations.yml, openbsd-rust.md, design_sweep.md and
session-2026-11-08.md across three working sessions, after cloning the
monorepo into a bounded Linux container, building a Ruby 4.0.5
toolchain from source, measuring the serial suite in four supervised
batches, and reading the operator's 2026-11-08 transcript as evidence.
This page is an experience record, not policy and not backlog
administration: it creates no Law identity, nothing loads it, and the
root TODO.md keeps owning action state. Each row names its state on
main - df46c8bf when this page first landed, 659503f2 for the
2026-11-09 updates - so a reader can tell landed from open without
trusting this page.

## For future LLMs

1. A claim-to-check map, generated and machine-readable. Evidence:
   three sessions re-derived which check carries which claim by
   reading laws.yml, checks/ and lib by hand; tools/agent_context.rb
   emits context but not the mapping. State on main: open. Landing
   path: an agent_context extension with a source test, no new
   registry. Update 2026-11-09: adjacent guidance landed without the
   map - handler success distinguished from verified effects
   (d9ef4f35, c6e389a3), skipped and inconclusive results named apart
   from failures (72c87366), execution evidence bounded and redacted
   before it reaches a model (d7e86529).

2. Environment-tagged skips. Evidence: the container measured 127
   failures and 62 skips at 4aa90499 and separated real breakage from
   foreign environment only by hand-triaging 199 failure blocks.
   State on main: open. Landing path: a tag convention in
   test_helper.rb and a summary line in the supervised runner.

3. First-class suite sharding and a baseline receipt. Evidence: the
   canonical MASTER_TEST_JOBS=1 rake test cannot finish inside a
   ten-minute tool call; the external agent rebuilt the Rakefile's
   worker command in a private driver outside the repo to measure
   9159 runs and 310053 assertions in four batches. State on main:
   open. Landing path: a batch task under the existing test namespace,
   plus the suite-report artifact the Rakefile already inspects.

4. A delivered receipt template. Evidence: AGENTS.md and
   expectations.yml carry the delivered bar in prose; every agent
   re-derives it per session. State on main: open. Landing path: /why
   renders the fill-in receipt (baseline hash, after hash,
   path-scoped diff, check name and result); render-only, with a test.

5. Prompt generated from the capability registry, identity pinned
   against the lane. Evidence: docs/session-2026-11-08.md, former open
   rows one and two. State on main: landed at df46c8bf — the boot
   prompt names the closed registry, the live voice state and the
   honest output boundary, and the identity block is held
   byte-identical across lanes by test_identity_and_runtime_surface.rb.

6. Swallow budgets. Evidence: session-2026-11-08.md, the rotation-race
   row — twenty-three swallowed ENOENTs filled one run's error summary
   before the race got a fix. State on main: landed at 5c752521 —
   PLACE_BUDGET = 3 in lib/ground/swallow.rb, the /fix summary groups
   swallowed errors by place and names any place past budget
   (lib/fix/run_ledger.rb), with tests in test_swallow.rb and
   test_run_ledger_per_run.rb; the 2026-11-09 transcript shows the
   summary line live ("errors swallowed this run 1 at 1 place(s)").

## For humans

7. A capability card at boot, and task-grouped help. Evidence: the
   transcript operator learned by trial that /tts was a spelling of
   /voice, that the zsh passthrough caps at thirty seconds, and that
   /narrate and /bard existed. State on main: partially landed —
   /help names the governed-shell cap and the one-shot boot shows lane
   evidence; capability discovery is exposed only when the catalog
   tool is present (50782097, fa2f9006) and read-only model status
   commands are documented (66e9f98f, da650670); the interactive
   welcome line still summarises state, not capability.

8. Provider errors classified with remediation. Evidence: thirteen
   lanes answered "User not found." and the transcript never names the
   wrong credential. State on main: landed as of 659503f2 — lane
   health classifies quota, unreachable, login and guessed waits with
   per-class remediation text (lib/io/lane_quota.rb), the dispatcher
   classifies auth and empty replies (02e61ff2, 189333bf, 81620c8b),
   and tests hold the classes and the recovery guidance (09813186,
   9bcd4474 in test_lane_pool.rb, test_llm_dispatcher.rb); the
   2026-11-09 transcript shows eleven skipped lanes each named with
   class, wait and next action.

9. A session post-mortem receipt. Evidence: the external agent built
   docs/session-2026-11-08.md by hand from a pasted transcript; MASTER
   watched the same session happen. State on main: open — run-level
   receipts and named discards appear in the 2026-11-09 transcript
   ("run ended reason=command scope ended", "receipt=not written
   (read-only)"), and a second page, docs/session-2026-11-09.md, was
   again built by hand; the chat-visible session receipt is still
   missing. Landing path: a read-only receipt over existing telemetry
   and the session log.

## Shared

10. Sibling trees as first-class /fix targets. Evidence:
    docs/openbsd-rust.md holds the sibling-checkout contract by path
    convention, and every run re-states the boundary by hand. State on
    main: open — no sibling target mechanism in the fix kernel.
    Landing path: a sibling target with the no-cross-tree-write
    boundary checked, plus tests.

## Where the action lives

No new register rows are filed with this page. The genuine external
prerequisites are already carried by the register: the voice proof on
real audio hardware sits in the TODO.md voice row (measure
time-to-first-audio, local fallback, truthful worker-failure
reporting), and the pinned-Ruby suite acceptance sits in register
section one. The register's stewardship rules forbid filing work that
current tools and authority can carry, and this page honours that:
each open row above needs its own authorisation to become work.

## Non-claims

This page records wishes and their evidence. A landed row names code
and tests on main, not a delivered claim; no row is scheduled by this
page, and none of it overrides soul.yml, laws.yml or the tree
contracts.
