# STUDIO

The source root has exactly four owners: `dilla/` (music and RG-69), `lora/` (subjects and selfie gallery), `postpro/` (image and film processing), and `replicate/` (shared runtime, CLI, checks, tests, and the Replicate client).

**STUDIO owns pub5's music, image and video tools.** Dilla, Postpro,
photograph, Replicate and the private LoRA tools live here. MASTER may call
them through compatibility symlinks under `MASTER/tools/`, but STUDIO owns
the implementations.

Project notes preserve provenance, source rights, consent, reproducibility
and the limits of each result. Their prose follows the shared editorial
standard in [MASTER/AGENTS.md](../../MASTER/AGENTS.md), without flattening the
voice of the creative work.

## The tools

- `dilla/` — the Ruby-only music engine, canonical music data, dependency-free
  spectral reference analyzer, and Ableton Live Set recovery tools. The recovered
  corpus records restoration provenance, per-chord bar spans, and whether timing
  is source-described or an engine grid assumption; measured melody fragments are
  not presented as complete transcriptions. The renderer remains owned by
  `dilla/dilla.rb`; the stdlib-only `dilla/lib/als*.rb` tools
  recover composition archives and MIDI from `.als` files. The unified
  `replicate/bin/studio` CLI exposes `dilla`, `postpro`, the subject-aware `lora`
  menu and validation/recovery commands, consent-gated `photograph` generation,
  publication-gated `gallery`, `promo`,
  and `ableton inventory|export|midi`.
  Generated output is append-only. A new run never replaces or deletes an
  earlier still, film, sidecar, source photograph, dataset, weight or model
  manifest. Existing renders remain available for comparison.
- `dilla/rg69/rg69.html`, `dilla/rg69/rg69.css` and `dilla/rg69/rg69.js` — the RG-69 browser beat machine. Its page, styles and application code are separate assets under MASTER's HTML Laws; Tone.js 14.8.49 is vendored in `dilla/vendor/tone/` with its MIT license and failure is reported visibly.
- `lora/selfies/selfies.html`, `lora/selfies/selfies.css` and `lora/selfies/selfies.js` — the selfie gallery. A Swiper
  rail (vendored and version-pinned in `lora/vendor/swiper/`) of a subject's stills
  and films over the dilla bed, built from the generated `lora/selfies/manifest.js`
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
- `lora/` — subject descriptors and private training plans.
  `replicate/bin/studio lora` opens the subject-aware menu. A default selfie series uses
  only that subject's pinned LoRA; it does not fall back to a generic face.
  The exact version must also be recorded in private `subject.env` as
  `LIKELINESS_REVIEWED_VERSION` after full-size comparison with approved
  reference photographs. Retrained or changed versions are blocked until reviewed.
  `ruby STUDIO/lora/photograph.rb --all-subjects --count 6` preflights Johann,
  Ragnhild and Merethe together and appends six subject-specific scenes each.
  Earlier generated stills and sidecars are always retained; no stale-render
  deletion path exists.
  `ruby STUDIO/lora/train.rb --all` validates all three private datasets,
  consent records, captions, shared settings and Replicate destination visibility
  before any upload, then trains sequentially and records immutable candidate
  versions without approving them. The shared `training_standards.yml` governs
  Replicate trainer pin, `training_steps=1000`, `lora_type=subject`, seed and
  the shared FLUX inference settings; there are no per-person rank/optimizer knobs.
  `ruby STUDIO/lora/review.rb --subject NAME --candidate` renders three private
  candidate samples after training, next to three approved source photographs,
  and writes a contact sheet plus Postpro measurements. Candidate renders stay
  under the subject's ignored `.cache/likeness-review/` tree; they cannot enter
  the published selfie folder or approve a model.
  The candidate step still requires all training consent and source-rights
  permissions; ZIP uploads also require a regular, singly-linked mode-0600 file
  and an explicitly private destination model. After comparing all candidate
  images at full size, record the exact immutable
  version in that subject's owner-only `subject.env` as
  `LIKELINESS_REVIEWED_VERSION`. A present `subject.env` cannot be a symlink or
  a shared-readable file. Private `weights/<MODEL>/replicate_training.json`
  manifests require owner-only directories and a singly-linked owner-only file;
  the tracked subject-root manifest remains a non-secret compatibility pin.
  Only then may the six-image batch run.
`ruby STUDIO/lora/photograph.rb --all-subjects --count 6` appends the three
  final series after each subject's own preflight succeeds. Earlier generations
  stay in place. Then run
  `ruby STUDIO/lora/review.rb --subject NAME` for each person to create final
  contact sheets and diagnostic reports. Open each private report's
  `index.html` to inspect every source and final portrait at full resolution;
  the page links the underlying local image files. This is a private review,
  not gallery publication. `selfies_gallery.rb` has a separate publication-
  consent gate and is not needed to inspect the finished portraits. Identity
  remains a human judgement; Postpro metrics are not face recognition.
  On the development checkout, run `MASTER/bin/fix-here STUDIO --lane all`
  after rendering to run MASTER's source, structural, behavioural and visual
  repair lanes over the STUDIO implementation. The review contact sheets and
  HTML reports are local visual evidence; screenshot review is only complete
  when those actual local artefacts exist. Keep private review artefacts local.
  `replicate/bin/studio lora validate [--json]` performs a read-only profile audit.
  `replicate/bin/studio lora recover` imports from a local, read-only pub4 checkout;
  it starts with a dry run. Applying a recovery requires private consent and
  separate source-rights evidence.

  Recovery copies only approved subject descriptors, pinned model manifests
  and explicitly selected source photographs. It never copies datasets, loose
  weights or renders. Source trees and evidence remain owner-only. Every
  generated series is append-only; no series command deletes earlier portraits,
  source photographs, datasets, weights or consent. Merethe's separate recovery command verifies the 15
  original Git blobs; it does not prepare a dataset. Merethe's preparation
  step builds in a private staging directory and preserves the last known-good
  dataset if a build fails.
- `lora/judge.rb` — audits whole-frame texture, highlight, clipping and
  tonal-range proxies. Highlight spread is assessed only when a frame contains
  highlight samples. The committed fallback floor is neutral until
  recalibration; the historical ceiling used the wrong direction. Calibration
  requires at least five regular reference images outside the checkout. By
  default, it prints path-free aggregate YAML. With `--output`, it writes a
  new mode-0600 file outside the checkout. `STUDIO_LORA_THRESHOLDS` selects
  a private override. These proxies do not replace full-size human review or
  calibrated perceptual ΔE fixtures.

## Shared surfaces

- `output_paths.rb` — where generated output is allowed to land. The render
  directory is absolute and must not collide with the checkout.
- `replicate/subprocess.rb` — the one child-process helper the tools share.
- `dilla/analog_core.rb` — a seeded, bounded filtered-noise source shared by Dilla tape-speed variation and Postpro's frame-to-frame gate weave; no added gem or native dependency.

## Outbound provider transport

`Studio::ReplicateClient` owns both Replicate API requests and prediction
asset downloads. The API origin and download hosts are constrained; downloads
require HTTPS on port 443 and the Replicate host allowlist. Both paths resolve
the hostname, reject the complete A/AAAA answer set if any address is private,
reserved, translated or non-global, and pin the socket to the approved public
address with `Net::HTTP#ipaddr`. The original hostname remains in use for TLS
verification and Host; implicit environment proxies are disabled. API exchanges
have a 180-second hard deadline in addition to socket-idle timeouts and the
response byte cap. Downloads retain atomic publication, symlink refusal, byte
caps and a monotonic deadline. Redirect responses are not followed.

Do not turn a provider-returned URL into an unrestricted fetch. Keep the host
allowlist, URL shape, pinned destination and transfer budgets together at the
provider boundary. If another STUDIO tool needs an external URL, give it an
explicit owner and the same resolve → classify every answer → pin → bound
request pattern; do not copy a weaker `Net::HTTP.start(host)` example.

## Operator workflow

`replicate/bin/studio doctor` gives a read-only local readiness report. Add `--json` for
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
replicate/bin/studio doctor --json
cd STUDIO && rake check test
```

Neither command substitutes for listening to a Dilla render, testing browser
interactions in a real browser, supplying real Ableton sets, or proving a live
provider transaction.

## Checks

`replicate/Rakefile` is the tree's check surface: `rake check` syntax-checks entrypoints
and audits the LoRA profiles, `rake test` runs the Dilla, Postpro motion,
Replicate, IdeaPicture, LoRA and private-preparation regressions, and `rake`
runs both. The test suite uses stubs and local temporary data; it does not need
a Replicate token or start paid training.

The FETAT writing project lives under `BIZ/fetat/`; its publishable proposal
source and renderer are BIZ-owned, not STUDIO policy or part of this check surface.
