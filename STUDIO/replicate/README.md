# STUDIO

The source root has four code owners: `dilla/` (music and RG-69), `lora/` (subjects and selfie gallery), `postpro/` (image and film processing), and `replicate/` (shared runtime, CLI, checks, tests, and the Replicate client). The root-level `test/` directory contains only two compatibility proof entrypoints; the canonical suites live under `replicate/test/`.

**STUDIO owns pub5's music, image and video tools.** Its tracked source
travels with the pinned full-repository checkout on vm23, and the full production
release runs STUDIO's check and test suite on the workstation before deployment.
STUDIO does not have a separate vm23 service target; renders, datasets, source
photographs and other private working output remain local. Dilla, Postpro,
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
  A gallery rebuild excludes any subject whose publication permission is absent
  or revoked, writes the restricted manifest atomically as an owner-only file,
  and reports `PARTIAL` without deleting the private media. A previous public
  manifest must be rebuilt after permission changes; this does not retract copies
  already downloaded or cached outside the local gallery.
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
  upload, so a mismatched shape fails before a paid call. This MiniMax
  reservation is a process-local per-run estimate, not a persistent daily
  account cap. The LoRA batch ledger is separate and checkout-local. Other
  paid model rows without a verified price are not treated as zero-cost or
  covered by either budget; do not infer an all-provider spend ceiling. The
  provider's native audio stays off: STUDIO lays the dilla bed under the cut
  itself.
  Each successfully downloaded film receives a private `.mp4.json` receipt
  binding its source still and output by SHA-256, with the model, prediction
  ID/status, any catalogue-based pre-request estimate, and explicit
  `NOT_REPORTED_BY_PREDICTION_API` actual-cost status. Visual and likeness review
  remain `NOT_REVIEWED`; the receipt is not an invoice or an approval.
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
  ruby STUDIO/lora/photograph.rb --all-subjects --count 4 preflights Johann,
  Ragnhild and Merethe independently before the first prediction. It renders only
  subjects whose own consent, pinned model and provider schema pass; one blocked
  subject no longer blocks another. The JSON reports per-subject RENDERED,
  INCOMPLETE, FAILED or BLOCKED state. Exit 1 means partial output; exit 2 means
  no subject was eligible. Earlier generated stills and sidecars are retained.
  Each selfie is then graded separately by
  `STUDIO/postpro/postpro.rb --heavy --count 1` through
  `IdeaPicture#render_still`. The provider original is preserved, Postpro
  writes a separately named graded sibling, and the append-only series ledger
  records the graded file as the final portrait. Review sheets use those
  per-image Postpro outputs, not the ungraded originals.
  The photographic quality gate is read-only:
  `ruby STUDIO/lora/lora.rb quality --json`. It validates the inference
  profile catalogue, training readiness, independent evaluation photographs
  and their separate review permissions; it makes no provider calls.
  Every subject's private `lora/<subject>/evaluation/` directory must contain
  5–24 approved photographs that are not in `dataset/`. Keep this directory
  owner-only (0700), and each photograph owner-only (0600), singly-linked,
  non-empty and byte-distinct from every training photograph. These are
  evaluation-only sources: never copy them into the training archive.
  They are used for local comparison only and are not uploaded or included in
  candidate-render requests; the candidate render uses the already trained,
  immutable LoRA version and the selected scene prompt.
  The subject's private `consent.yml` must separately grant
  `subject_consent.likeness_review: true` and include
  `likeness_review` in its subject-consent evidence `covers`; its
  `source_rights` must grant `review_use: true` and include an
  `evaluation_photographs` evidence entry covering `review_use`, backed by
  a separate private evidence file. The regular training and provider
  permissions remain independently required for candidate rendering.
  Candidate LoRA comparison accepts `--profile identity|balanced|detail|draft`,
  for example
  `ruby STUDIO/lora/review.rb --subject johann --candidate --profile identity`.
  Profiles are controlled starting points, not quality rankings. Keep the
  scene, seed, approved model version and holdout set fixed when comparing
  them; inspect every finalist at full size and leave the model version
  unapproved until a human has reviewed the likeness and photographic rubric.
  Selfie-series inference can select the same profile with
  `--inference-profile balanced`. The balanced profile is the default.
  The first four scenes for each subject use an original, coordinated
  autumn/winter ’26 wardrobe direction: Johann gets textured wool, a long
  chore coat, waffle-knit layering and a clean suede blouson; Ragnhild and
  Merethe get structured tailoring, oxblood/chartreuse accents, velvet,
  charmeuse, leather, suede and shearling. The clothing silhouettes and fabrics
  are editorial references, not copies of specific products; the prompts do
  not add retailer logos or branding. The direction follows
  [NET-A-PORTER’s FW26 trend report](https://www.net-a-porter.com/en-gb/porter/article-c99dca08ba956cfc/fashion/art-of-style/fw26-fashion-trends),
  [GQ’s A/W 2026 menswear edit featuring MR PORTER selections](https://www.gq-magazine.co.uk/article/autumn-winter-2026-menswear-trends)
  and [MR PORTER Norway’s clothing range](https://www.mrporter.com/en-no/mens/clothing).
  `ruby STUDIO/lora/train.rb --all --approve-spend-usd 5.00` validates all
  three private datasets, consent records, captions, shared settings and
  Replicate destination visibility before any upload, then trains sequentially
  and records immutable candidate versions without approving them. The
  explicit `--approve-spend-usd` ceiling is mandatory; it is the total
  client-side budget for this batch, not an automatic purchase authorisation.
  Each job's local wait timeout is bounded by the remaining amount and the
  pinned trainer rate. The 60-second minimum compute reservation and
  10-second cancellation margin are local policy values, not Replicate minimums.
  On timeout the client requests cancellation and checks the provider status
  before it continues. Replicate documents `Cancel-After`
  for predictions, not as a guaranteed training deadline, so this is not a
  provider-enforced or account-wide hard USD cap. If cancellation remains
  unconfirmed, the run stops and reports `SPEND_UNVERIFIED`; a still-running
  provider job may continue to incur charges. The current trainer pin uses
  8× Nvidia H200 at
  USD 0.0122 per compute-second (verified 2026-11-22; source and date live in
  `training_standards.yml`). Terminal provider `metrics.predict_time` is
  multiplied by that rate and recorded as a calculated estimate, never as an
  invoice or a settled card charge. If a request has no terminal compute metric,
  or the provider does not confirm cancellation after a timeout, the batch
  stops before the next training and reports `SPEND_UNVERIFIED`. Each batch also appends a private mode-0600
  receipt to `STUDIO/lora/.cache/training-spend.jsonl`, including failed and
  budget-stopped results while omitting provider error bodies and signed URLs.
  The local receipt records computed usage, not an invoice. A private
  `.cache/training-spend.lock` serialises training batches in this checkout
  only; it is not an account-wide or cross-device spend lock. Do not start
  concurrent training from another checkout. The shared `training_standards.yml`
  governs the trainer pin, `training_steps=1000`, `lora_type=subject`, seed and
  shared FLUX inference settings; there are no per-person rank/optimizer knobs.
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
  Only then may the four-image batch run.
`ruby STUDIO/lora/photograph.rb --all-subjects --count 4` appends the three
  final series after each subject's own preflight succeeds. Earlier generations
  stay in place. Then run
  `ruby STUDIO/lora/review.rb --subject NAME` for each person to review only the
  latest recorded four-image series. The ledger keeps earlier generations out
  of the current contact sheet while preserving every old still and sidecar.
  Open each private report's
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
