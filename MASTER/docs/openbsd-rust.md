# openbsd-rust

openbsd-rust is the operator's project to port OpenBSD to Rust. It lives in
its own git repository outside this checkout and retains its own history, owner and
proof obligations. This page defines the intended external-target contract; it does
not claim that the current /fix pipeline already supports sibling checkouts.
MASTER can provide guidance, but pub5's /fix transaction boundary must not be
widened by treating a foreign path as an ordinary in-repository target.

## Tree shape: one MASTER, many roots

    ~/src/pub5/              # this checkout; MASTER/bin/master is the one CLI
    ~/src/openbsd-rust/      # the port project; its own git root, history and remote
    ~/src/openbsd-src/       # optional local OpenBSD src checkout for patch work
    ~/src/vendor/sequel/     # external clones, one root each

Each target has one root and one owner. Nothing is vendored into pub5: a dual home
(docs here, code there) and absorbed history are the anti-pattern.

`bin/master core --root ~/src/openbsd-rust --real GOAL` invokes the separate,
provider-backed Core fold against that root and requires provider credentials. Without
`--real`, CoreCommand runs its scripted constitution self-test; it does not pursue
the supplied goal. This interface is not the /fix scanner, repair loop or delivery
proof pipeline, and its result must not be described as a completed /fix run.

The current /fix target resolver refuses absolute paths outside pub5's governed trees
before observation. `/fix <absolute path> --dry-run` therefore does **not** inspect
a sibling checkout today. FixPlan pins targets inside its root, and TaskContract
accepts repository-relative scope only. Do not relax those checks to make a path
resolve: the sibling-target /fix adapter remains open and must start with a strictly
read-only observer, then prove that local transactions, commits and cleanup cannot
write into the foreign checkout. Until that boundary exists, inspect and change an
external project with its own tools from its own Git root, and run that project's
own check.

## The loop

There is no separate scan command: observation is where a fix starts, not a second pipeline.
`/scan` is a compatibility rewrite to `/fix --mode=repair --dry-run`; the
deterministic lexical check remains available with `MASTER_SCAN_DETERMINISTIC=1`. The
staged writes (`Fix::Transaction` for per-file repairs and `Fix::Restructure` for
multi-file moves) are bound to this checkout's repository scope. They are not an
external-repository writer, and `--dry-run` does not make an unsupported sibling
target readable. A future adapter must establish external read-only observation
first; any subsequent external edit must be applied and checked from the target's
own Git root through its own transaction and test authority. Delivery keeps its
three proofs, all three or nothing:

1. **Hashes** — baseline and after, over the scoped paths.
2. **Diff** — path-scoped, reviewable, small. OpenBSD culture reviews small diffs; a
   rewrite of `sys/` in one pass is refused by taste before any tool sees it.
3. **Check** — one command tied to the claim; the exit status decides.

A run that stopped is stopped, not delivered. A check that did not run is
INCONCLUSIVE, never PASS.

Path protection has one authority. This page does not define a second
"sacred path" list: `MASTER/data/soul.yml#absolute.sacred_paths` is the current
source for any globally protected paths, and is empty in this checkout. Other
preservation, task-scope and write refusals continue to come from the applicable
Laws and executable gates.

## First check command

The first check for the port tree is its build smoke, run on OpenBSD itself — Linux
CI is not the platform, and Rust-on-OpenBSD bootstrap, packaging and ABI constraints
make proof-on-platform the whole point:

    cd ~/src/openbsd-rust && cargo build --workspace && cargo test

The concrete command is fixed when the tree exists; the contract is fixed now: it
runs on OpenBSD, it builds or tests the claimed surface, it exits nonzero on
failure, and it needs no network. Until that command exists, nothing about the port
is deliverable — `not_probed` is the honest status for an operation no run has
exercised.

## Targets and their checks

Map each root to the one check that proves its claim. If a root has no entry, the
apply step names its check explicitly, so delivery never assumes a silent default.

| Root | Check that can fail | Notes |
| --- | --- | --- |
| `~/src/pub5` (this checkout) | `bin/test`; per tree: `cd MASTER && bundle exec rake test`, `ruby RAILS/test/run_all.rb`, `ruby OPENBSD/test/run_all.rb`, `cd STUDIO && bundle exec rake check test`; `bin/check --profile=agent` | the primary case |
| `~/src/openbsd-rust` | `cargo build --workspace && cargo test`, on OpenBSD | the first check, defined above |
| `~/src/openbsd-src` | a build of the touched subsystem, e.g. `make -C usr.bin/foo` | patches go upstream through sendbug and tech@, never around OpenBSD's process |
| `~/src/vendor/sequel` | `bundle exec rake test` — the project's own suite | per clone, per run; gate on their tests, contribute by PR |
| Jeremy Evans' other repos | each clone's own suite (`rake test`, `rspec`) | name the list per run; "all repos" is an operator loop, not one command |

## What never counts as delivered

- "Rust is now an official OpenBSD language" — upstream adoption is OpenBSD's
  decision, not a diff.
- "The kernel boots" — no boot on hardware, no claim.
- "Upstream merged it" — a merged pull request belongs to the upstream project's
  record, not to a run here.
- A fix recorded without the target tree's own check.
- Any claim whose only evidence is a diff in this checkout.

MASTER helps the software side of openbsd-rust — tree, build scripts, packaging,
patches, proof — with the same refusal to false-pass it applies at home. Scope
classification for this and every other standing ambition lives in
[expectations.yml](expectations.yml).
