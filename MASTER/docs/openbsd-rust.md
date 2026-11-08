# openbsd-rust

openbsd-rust is the operator's project to port OpenBSD to Rust. The project lives in
its own git repository outside this checkout; MASTER governs that tree under the same
proof rules as every other target — observe, scoped change, one check that can fail —
and never becomes the port itself. This page is the layout contract: the tree shape,
the loop, the first check, the target-to-check map, and the claims that never count
as delivered.

## Tree shape: one MASTER, many roots

    ~/src/pub5/              # this checkout; MASTER/bin/master is the one CLI
    ~/src/openbsd-rust/      # the port project; its own git root, history and remote
    ~/src/openbsd-src/       # optional local OpenBSD src checkout for patch work
    ~/src/vendor/sequel/     # external clones, one root each

Each target has one root and one owner. Nothing is vendored into pub5: a dual home
(docs here, code there) and absorbed history are the anti-pattern. MASTER addresses a
root by path. `bin/master core --root ~/src/openbsd-rust GOAL` drives the fold spine
against that root, and `/fix <absolute path> --dry-run` observes it read-only against
pub5's Laws.

## The loop

There is no /scan: observation is where a fix starts, not a command. `/fix <path>
--dry-run` is the read-only pass. The fix gate's staged writes (`Fix::Transaction`
for per-file repairs, `Fix::Restructure` for multi-file moves, the `WriteGuard` and
the sacred-path refusal ahead of every write) are built for this checkout's trees; in
a foreign checkout the same proofs apply with the roles swapped — observation through
`--dry-run` against the absolute path, the change applied in the target's own git
root, the target's own suite as the check. Delivery keeps its three proofs, all
three or nothing:

1. **Hashes** — baseline and after, over the scoped paths.
2. **Diff** — path-scoped, reviewable, small. OpenBSD culture reviews small diffs; a
   rewrite of `sys/` in one pass is refused by taste before any tool sees it.
3. **Check** — one command tied to the claim; the exit status decides.

A run that stopped is stopped, not delivered. A check that did not run is
INCONCLUSIVE, never PASS.

Sacred paths stay sacred: `data/laws.yml`, `data/soul.yml`, `data/project_context.yml`,
`lib/soul.rb`, `lib/ground/pledge.rb` and `bin/master` are refused to automated
writers, and external work never edits them.

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
