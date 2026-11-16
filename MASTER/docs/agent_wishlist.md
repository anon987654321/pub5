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
   emits context but not the mapping. State on main: landed at
   ee13e18 — opt-in agent_context --json --checks projects every check's
   declared claim, implementation, prerequisites and composite from the
   existing checks.yml; regression tests compare the projection with every
   registry row. It is a map of declarations, not execution evidence.
   Update 2026-11-09: adjacent guidance landed without the
   map - handler success distinguished from verified effects
   (d9ef4f35, c6e389a3), skipped and inconclusive results named apart
   from failures (72c87366), execution evidence bounded and redacted
   before it reaches a model (d7e86529).

2. Environment-tagged skips. Evidence: the container measured 127
   failures and 62 skips at 4aa90499 and separated real breakage from
   foreign environment only by hand-triaging 199 failure blocks.
   State on main: landed in this revision — test_helper.rb emits explicit
   environment-tag markers, the supervised runner groups them by tag in
   its JSON receipt and prints tagged versus unclassified skip counts.
   Chrome-dependent fixtures now use the convention. Unconverted skips
   remain unclassified, not silently attributed to an environment.

3. First-class suite sharding and a baseline receipt. Evidence: the
   canonical MASTER_TEST_JOBS=1 rake test cannot finish inside a
   ten-minute tool call; the external agent rebuilt the Rakefile's
   worker command in a private driver outside the repo to measure
   9159 runs and 310053 assertions in four batches. State on main:
   landed in this revision — rake test:batch (MASTER_TEST_BATCHES=4)
   runs deterministic size-balanced shards under one suite lock,
   preserves each batch's worker logs and receipt, and replaces the
   running marker in suite-report.json with an aggregate baseline only
   after every batch finishes. The receipt records revision, Ruby,
   test-file fingerprint, counts and worker outcomes.

4. A delivered receipt template. Evidence: AGENTS.md and
   expectations.yml carry the delivered bar in prose; every agent
   re-derives it per session. State on main: landed in this revision —
   /why receipt (also /why delivery_receipt) renders a read-only template
   for baseline and after hashes, exact path-scoped diff, falsifiable check,
   observed result and Law assessment. Placeholders cannot become evidence;
   a test holds the fields and alias.

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
   /narrate and /bard existed. State on main: landed in this revision —
   compact and verbose splash modes render a task card from the same
   COMMAND_CATEGORIES and command_surface used by /help. It names only
   registered CLI groups, not provider reachability or plugin execution;
   /help remains the detailed command index. Renderer tests hold the
   category ordering and splash inclusion.

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
   watched the same session happen. State on main: landed in this revision —
   /session receipt summarizes the active transcript fingerprint, role/layer
   counts, bounded activity and evidence event names, and failure-like event
   counts. It never emits message text, tool arguments or event payloads;
   corrupt or unreadable sources produce INCONCLUSIVE. Tests cover privacy
   and corrupt telemetry.

## Shared

10. Sibling trees as first-class /fix targets. Evidence:
    docs/openbsd-rust.md describes external roots, but the live resolver
    rejects them before observation. State on main: open and explicitly
    bounded — regression coverage now proves that an existing sibling
    checkout directory and file are refused. FixPlan also requires the
    target to remain inside its pinned root, and TaskContract scope is
    repository-relative. The documentation now distinguishes the separate
    `bin/master core --root PATH --real GOAL` interface from /fix; the
    default CoreCommand self-test is not a goal run. Remaining work: a
    dedicated read-only external observer, then an independently proven
    write boundary in the target's own Git root. Do not relax the current
    refusal as a shortcut.

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

## GLM agent wish list (2026-11-17)

Provenance: written by the GLM session that cloned pub5 into a keyless
Debian sandbox, built a Ruby 3.3.13 userland toolchain, wired the
zai-cli lane as the primary /fix gateway, and ran governed /fix
segments against all five trees. Same standing as the page above: an
experience record, not policy; state on main names the commit that
carried each row.

1. A CLI-lane bridge must never pass the prompt as one argv value.
   Evidence: the first zai-chat bridge shelled out to
   `z-ai chat -p "$(cat file)"`; one argv cannot exceed the kernel's
   MAX_ARG_STRLEN (~128 KiB), so every repair-sized prompt died with
   E2BIG before leaving the machine, the lane parked itself, and the
   run crawled the free floor. State on main: landed — bin/zai-chat
   reads stdin with no ceiling and posts through the operator's SDK
   (18104b12); a 150 KiB prompt answers in ~14s, measured.

2. When a lane joins a class, the class's gates must learn it the same
   day. Evidence: zai-cli joined the subscription-CLI class on
   2026-11-16; KEYLESS_LANE_PREFIXES, LaneSelection::CLI_BINARIES and
   the tier chains all still lacked it, so a keyless host refused the
   pinned lane, the probe recorded it dead, and the router's
   availability gate then refused the run as "routing disagrees with
   provider availability". State on main: landed — prefix, binary map,
   subscription list and default/primary/strong chain rows
   (088c5127, 0b4628fb, d70ff415), with two guard tests in
   test_lane_policy_from_yaml.rb so the next lane cannot land half in.

3. A verifier must compare against its own baseline. Evidence: the
   focused-test verifier refused every repair whose mapped suite came
   back red, including suites red before the run started — four
   environment failures in test_lane_selection.rb vetoed all work on
   files the suite touches, all run long. State on main: landed —
   AutofixGuard captures the pre-repair verdict and refuses only a
   raised failure/error count (10486829).

4. A consensus jury must be seatable on the hosts that run /fix.
   Evidence: the pool named claude-sonnet-5-5, grok-cli:auto and
   moonshotai/kimi-k2 — no key on the current hosts reached any of
   them, so every error/critical repair failed closed for want of a
   quorum. State on main: landed — the jury rides zai-cli:auto,
   ovh:gpt-oss-120b and kilo:nvidia/nemotron-3.5-lightning:free, each
   answered live on 2026-11-17, spanning three families so the
   author-family exclusion always leaves two independent voters
   (088c5127). The doctor check landed as a report-only runtime probe
   (eef87efa, c43916fd, af0f5add): each configured juror is checked through
   ModelRouter's live lane diagnosis, and quorum plus the independent-family
   floor must survive exclusion of every possible author family. A timed-out
   provider probe is UNMEASURED, not PASS. Remaining work: make /fix consume
   this readiness result as a preflight before spending its repair budget;
   the current check does not impose that admission gate.

5. A fresh clone must be runnable as cloned. Evidence: five files in
   MASTER/bin shipped mode 100644 — including the zai-chat bridge — so
   the lane died with permission denied on any fresh checkout.
   State on main: landed — exec bits fixed in the index (088c5127).

6. Landscape tests must not assert live third-party listings.
   Evidence: test_keyless_routing previously pinned a currently listed
   llm7 model, which rotates without a repository change. State on main:
   landed at 01c617c — the reachability test now injects a fixed hosted
   catalogue fixture and still exercises Master.llm_reachable?; the
   remaining llm7 rows in that file are explicit local fixtures, not live
   listings.
7. One boot without re-loaded law files. Evidence: the reported duplicate
   constant warnings named law/brand.rb and law/cosmetic.rb. Static trace
   found that Law.load_all already skips reload when the sorted source set,
   size/inode/mtime stamps and registered definition IDs are unchanged;
   LawTree.load! calls it unconditionally, but that call should hit the
   existing no-op path. State on main: open; no safe code change yet. The
   warning therefore points to an actual source-stamp change, registry
   invalidation, or a second law root being loaded in the same process.
   Next step: capture reload reason, directory and changed source paths at
   Law.reload's existing boundary, then reproduce before changing semantics.
   Do not hide the warning with constant guards or disable reload globally.
8. Run journals that survive the checkout. Evidence: the sandbox
   recycled mid-session and took .master/ with it; a resumable run is
   only as durable as the directory holding it. State on main: open —
   a relocatable MASTER_STATE_DIR (or the like) is wanted; the shim's
   .tools/ruby path already shows the pattern for Ruby itself.
8. Run journals that survive the checkout. Evidence: the sandbox
   recycled mid-session and took .master/ with it; a resumable run is
   only as durable as the directory holding it. State on main: open.
   Static trace shows the lifecycle state is a family, not one file:
   fix_runs.json, its lock and pending marker, assessment reports and
   architecture reports all live below the workspace's .master directory.
   Receipts store paths relative to the workspace, and the readers/writers
   validate parent identity, permissions, links and containment. Moving
   only the main JSON would leave evidence unresolvable or weaken those
   checks. A safe change must relocate the whole state family, define
   stable receipt path semantics, and preserve atomic writes, locking,
   observer boundaries and restart recovery.
9. Rate-limit pacing belongs to the run, not to the operator's wrist.
   Evidence: three stream workers plus lane probes plus the consensus
   jury pushed the z-ai gateway into 429s twice in one session; the
   lane has no declared concurrency ceiling, so nothing in the pipeline
   backed off before the provider said so. State on main: open — a
   per-lane concurrency ceiling in models.yml cli_lanes, read where
   CLI_SLOTS is read today, is the smallest honest shape.
