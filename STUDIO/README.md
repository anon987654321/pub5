# STUDIO

**The media tools live here, each with one physical home and no second tree.**
STUDIO holds Dilla, Postpro, photograph, Replicate and the private LoRA tools. MASTER's runtime may
call into these tools through compatibility symlinks under `MASTER/tools/`,
but the implementation is owned here.

## The tools

- `dilla/` — the Ruby-only music engine, canonical music data, dependency-free
  spectral reference analyzer, and Ableton Live Set recovery tools. The recovered
  corpus records restoration provenance, per-chord bar spans, and whether timing
  is source-described or an engine grid assumption; measured melody fragments are
  not presented as complete transcriptions. The renderer remains owned by
  `dilla/dilla.rb`; the stdlib-only `dilla/lib/als*.rb` tools
  recover composition archives and MIDI from `.als` files. The unified
  `bin/studio` CLI exposes `dilla`, `postpro`, the subject-aware `lora`
  menu and validation/recovery commands, consent-gated `photograph` generation,
  publication-gated `gallery`, `promo`,
  and `ableton inventory|export|midi`.
  Rendered output is replaceable:
  a new run may delete and replace it, and no rendered-sound default moves on
  one person's judgement.
- `rg69.html`, `rg69.css` and `rg69.js` — the RG-69 browser beat machine. Its page, styles and application code are separate assets under MASTER's HTML Laws; Tone.js 14.8.49 is vendored in `vendor/tone/` with its MIT license and failure is reported visibly.
- `selfies.html`, `selfies.css` and `selfies.js` — the selfie gallery. A Swiper
  rail (vendored and version-pinned in `vendor/swiper/`) of a subject's stills
  and films over the dilla bed, built from the generated `selfies/manifest.js`
  and captioned for a screen reader. Films are muted inline loops with a
  poster-first frame; the bed never autoplays. `lora/selfies_gallery.rb`
  scans generated renders under `lora/` and writes that manifest — it reads
  only, and requires separate publication consent plus source-rights evidence
  for every included subject. Renders and source media stay local-only; older
  public Git objects still need separate repository-visibility and history cleanup.
- `lora/photograph.rb` and `lora/idea_picture.rb` — the image-generation
  entrypoint and its IdeaPicture implementation. A still renders from an engine
  chosen with `--engine`; a film animates it from an engine chosen with
  `--film-engine`, defaulting to MiniMax H3 Highspeed at 768P. MiniMax H3 Lite is
  selectable for drafts (480P by default, or `--film-resolution 768P`), with
  the rest of `models.yml`'s `image_to_video` catalogue (Kling v3 Omni included)
  available too. Both H3 models accept 4-15 seconds and support reference-driven
  generation. Their 50% Replicate promotion is modelled through December 31,
  2026; list pricing resumes automatically after that date. STUDIO reserves
  output and maximum reference-video cost against a $1 per-call and $5 per-run
  MiniMax H3 video budget before a prediction starts. `STUDIO_VIDEO_CALL_CAP_USD`
  and `STUDIO_VIDEO_BUDGET_USD` can lower those ceilings, never raise them.
  Each film engine declares the input
  keys it takes, and the renderer preflights the model's own schema before any
  upload, so a mismatched shape fails before a paid call. The provider's native
  audio stays off: STUDIO lays the dilla bed under the cut itself.
- `replicate/client.rb` — the Studio-owned Replicate provider client
  (`Studio::ReplicateClient`), with version-aware input-schema reads, bounded
  transfers and explicit provider errors. `train_lora`, `upload_file` and
  `upload_zip` require a `subject:` keyword and stay bound to that subject's
  directory. The shared `lora/consent.rb` gate requires action-scoped written
  subject permission and separate rights evidence for every local source set.
  MASTER has its own client
  and runtime policies; this one is STUDIO's.
- `lora/` — subject descriptors and private training plans. `bin/studio lora`
  opens the subject-aware menu; `bin/studio lora validate [--json]` performs
  the read-only profile audit, and `bin/studio lora recover` is a dry-run-first
  importer from a local, read-only pub4 checkout. Applying it requires valid
  private consent and separate source-rights evidence. It copies only approved
  subject descriptors, pinned model manifests and explicitly selected source
  photographs — never datasets, loose weights or renders. Source trees and
  evidence are owner-only, and generated replacement series archive prior
  portraits only after every requested new render succeeds. Merethe's separate
  recovery command verifies the 15 original Git blobs and does not prepare a
  dataset. Merethe's preparation step builds in a private staging directory
  and preserves the last known-good dataset if a build fails.
  - The Replicate client is also an outbound-network boundary. API URLs are
    restricted to the canonical HTTPS API origin; output downloads are restricted
    to `replicate.com` / `replicate.delivery` hosts on HTTPS port 443. DNS names
    are syntax-bounded, every IPv4 and IPv6 answer must be public, and a mixed
    answer set is refused. Mapped IPv4, NAT64, 6to4, Teredo, private, loopback,
    link-local, multicast, documentation and reserved ranges are blocked. The
    socket is pinned with `Net::HTTP#ipaddr=` while the original hostname is
    retained for TLS. Proxies are disabled, unsupported pinning is a hard error,
    redirects are not followed, and transfers have byte and deadline caps.
  `lora/judge.rb` audits whole-frame texture, highlight, clipping and tonal-range proxies.
  Highlight spread is only assessed when a frame has highlight samples; the
  committed fallback floor is neutral until recalibrated because the historical
  ceiling used the wrong direction. Calibration requires at least five regular
  reference images outside the checkout; it prints path-free aggregate YAML by
  default, or writes a new mode-0600 file outside the checkout with --output.
  STUDIO_LORA_THRESHOLDS selects a private override. These proxies do not replace
  full-size human review or calibrated perceptual ΔE fixtures.
- `promo.rb` — cut a subject's stills into one vertical motion-graphics clip
  with a soundtrack. A slow push on each still, a crossfade between stills, one
  film look over the whole piece and the dilla render underneath. It composes
  ffmpeg directly rather than the per-frame in-process grade, which is the right
  tool for a shot clip but measured minutes for a four-second 1080p one. A
  render writes the MP4 plus a `.promo.json` sidecar naming every input.

## Shared surfaces

- `output_paths.rb` — where generated output is allowed to land. The render
  directory is absolute and must not collide with the checkout.
- `subprocess.rb` — the one child-process helper the tools share.
- `analog_core.rb` — a seeded, bounded filtered-noise source shared by Dilla tape-speed variation and Postpro's frame-to-frame gate weave; no added gem or native dependency.

## Outbound provider transport

`Studio::ReplicateClient` owns both Replicate API requests and prediction
asset downloads. The API origin and download hosts are constrained; downloads
require HTTPS on port 443 and the Replicate host allowlist. Both paths resolve
the hostname, reject the complete A/AAAA answer set if any address is private,
reserved, translated or non-global, and pin the socket to the approved public
address with `Net::HTTP#ipaddr`. The original hostname remains in use for TLS
verification and Host; implicit environment proxies are disabled. Downloads
also retain atomic publication, symlink refusal, byte caps and a monotonic
deadline. Redirect responses are not followed.

Do not turn a provider-returned URL into an unrestricted fetch. Keep the host
allowlist, URL shape, pinned destination and transfer budgets together at the
provider boundary. If another STUDIO tool needs an external URL, give it an
explicit owner and the same resolve → classify every answer → pin → bound
request pattern; do not copy a weaker `Net::HTTP.start(host)` example.

## Operator workflow

`bin/studio doctor` gives a read-only local readiness report. Add `--json` for
machine-readable output. It checks the Ruby baseline, required entrypoints,
output-path safety, local LoRA profile structure, optional media executables,
the current Git index and private paths in reachable local branches/tags.
A shallow clone is INCONCLUSIVE rather than reported clean. It makes no
provider calls, does not upload, render, modify consent, or rewrite Git history.
Other clones and remote mirrors remain outside a local check. A private-media
finding remains BLOCKED until the separate operator rights/history decision is
resolved; it is not silently converted into a pass.

The regular verification path is:

```sh
bin/studio doctor --json
cd STUDIO && rake check test
```

Neither command substitutes for listening to a Dilla render, testing browser
interactions in a real browser, supplying real Ableton sets, or proving a live
provider transaction.

## Checks

`Rakefile` is the tree's check surface: `rake check` syntax-checks entrypoints
and audits the LoRA profiles, `rake test` runs the Dilla, Postpro motion,
Replicate, IdeaPicture, LoRA and private-preparation regressions, and `rake`
runs both. The test suite uses stubs and local temporary data; it does not need
a Replicate token or start paid training.

The FETAT writing project lives under `BIZ/fetat/`; its publishable proposal
source and renderer are BIZ-owned, not STUDIO policy or part of this check surface.
