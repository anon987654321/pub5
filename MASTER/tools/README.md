# Tools

**MASTER keeps its instruments in plain sight and holds them to the same
standard as the code they measure, because a measurement nobody has checked is
only an opinion that happens to carry a number.**

This directory contains the operators, scanners, audits and inventories
that maintain the repository. Most are small Ruby programs with one clear
responsibility. The operator exposes the main entrypoints:

- `bin/operator measure` reports the ratchets and measurements.
- `bin/operator lint` applies the Laws without a model.
- `bin/operator doctor` checks the environment for known hazards.
- `sweep.rb` runs the census instruments in one pass and writes their
  findings in dmesg form. It measures and proposes; it never edits.

## Directory map

- `audit/` contains substantive registry, reachability and hygiene audits.
  Stable one-command endpoints whose implementations already live in
  `lib/` remain at this directory's top level. The former root paths for
  the audit family were removed; no compatibility entrypoints remain.
- `repo/` contains tracked-tree inventory and entrypoint reachability. `snapshot.rb` remains a top-level
  operator command until its reader/writer contracts are verified
  independently.
- `research/` contains cognition outcome benchmarks, mutation-oriented
  challenge checks and LLM trajectory reports.
- `audit/design_baseline.rb` measures the repository's design baseline.
- `rails/` contains Rails tooling. The operator exposes it through
  `triangle` (boot the live Brgen, Amber, BSDPorts and MASTER-face
  entries), `premerge`, `ci` and `coverage`. The same directory builds
  stylesheets and the route manifest, crawls apps with a browser, and holds
  Rails convention checks.

Several top-level tools serve cross-tree contracts:

- `agent_context.rb` prints the Law and tree map agents must read before
  working. Its `--json` option serializes the same standing context
  (conduct, blocking rules, coverage and shell contract); `--tree` adds
  the selected tree map. Harnesses and session handoffs can consume the
  JSON without parsing prose.
- `coverage_reconciliation.rb` compares tracked files with the instruments
  claimed in `checks/data/coverage_map.yml`. It reports INCONCLUSIVE while
  that map is marked partial, then fails on uncovered files once the map
  declares itself complete.
- `diff_routes.rb` accepts paths, a `--diff` base or `--stdin`, then
  prints the governing `PATH_OWNERSHIP.yml` rows and their declared checks.
  It exits 1 and names any path no row claims. It does not add a second
  path-to-check table.
- `snapshot.rb` backs `bin/operator snapshot`. It writes one snapshot per
  tree for another model to read; `--mirror` creates the byte-exact pack.
- `gap_discipline.rb` checks the chain from absence to implementation:
  `data/gaps.yml` identifies missing capabilities;
  `data/ideations/*.yml` records candidates and the reasons losers were
  rejected; `convergence.yml` records the resulting workstreams. It fails
  when critique rejects a picked candidate, a real choice has too few
  candidates, a picked gap has no workstream, or a workstream has no
  corresponding gap.

Media implementations belong to `STUDIO/`. The two compatibility links
that remain here are `dilla` and `replicate`; STUDIO owns their targets and
contracts. Invoke Postpro through `STUDIO/postpro`, not through a MASTER
link. Read the owning project README before changing media behavior. Do not
add a second implementation here.

## Read this part first

A measurement can be wrong even when its output looks precise. Before
trusting a finding, compare the instrument's source with a case whose answer
you already know. A greyscale test image once made a colour effect look dead.
A parallel sum changed in its last digit even when the input stayed steady.
When the result is unstable, hash the output and investigate the source of
the variation.

Declarations with no reader are the dominant defect. A preset names a setting
that no effect consults, a call passes an argument that the callee does not
accept and a rescue hides the error, and the feature never runs while every
report says it did. Before you trust a setting, find its reader. Before you add
a fix, consider adding the check that would have caught the fault.

Use Ruby and zsh, not GNU text tools. The repository deploys to OpenBSD, where
sed, awk, find, head, tail and wc behave differently, and perl and python are
banned in shell calls and committed scripts.

Tests here must prove something. `mutate.rb` changes a source, runs its test and
restores the file, because a test that stays green when the comparison it
covers is inverted proves nothing. Run the smallest check that proves the
work, and do not report done without its output.

## Checks

The Rakefile in this directory defines the checks. The test task runs the check
and event-bus suites, and the check task parses and loads every tool.

```zsh
cd MASTER/tools && rake test
cd MASTER/tools && rake check
```
