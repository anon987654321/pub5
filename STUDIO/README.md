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
  `bin/studio` CLI exposes `dilla`, `postpro`, `lora` validation, `promo` and
  `ableton inventory|export|midi`.
  Rendered output is replaceable:
  a new run may delete and replace it, and no rendered-sound default moves on
  one person's judgement.
- `rg69.html`, `rg69.css` and `rg69.js` — the RG-69 browser beat machine. Its page, styles and application code are separate assets under MASTER's HTML Laws; Tone.js 14.8.49 is loaded from a version-pinned CDN and failure is reported visibly.
- `selfies.html`, `selfies.css` and `selfies.js` — the selfie gallery. A Swiper
  rail (vendored and version-pinned in `vendor/swiper/`) of a subject's stills
  and films over the dilla bed, built from the generated `selfies/manifest.js`
  and captioned for a screen reader. Films are muted inline loops with a
  poster-first frame; the bed never autoplays. `lora/selfies_gallery.rb`
  scans `lora/` and writes that manifest — it reads only, and renders and
  generated renders are ignored going forward; source photographs already in
  history require separate repository-visibility and history cleanup.
- `lora/photograph.rb` and `lora/idea_picture.rb` — the image-generation
  entrypoint and its IdeaPicture implementation. A still renders from an engine
  chosen with `--engine`; a film animates it from an engine chosen with
  `--film-engine`, defaulting to MiniMax H3 Lite and offering the rest of
  `models.yml`'s `image_to_video` catalogue (Kling v3 Omni included). Each film
  engine declares the input keys it takes, and the renderer preflights the
  model's own schema before any upload, so a mismatched shape fails before a
  paid call. The provider's native audio stays off: STUDIO lays the dilla bed
  under the cut itself.
- `replicate/client.rb` — the Studio-owned Replicate provider client
  (`Studio::ReplicateClient`), with version-aware input-schema reads, bounded
  transfers and explicit provider errors. `train_lora`, `upload_file` and
  `upload_zip` require a `subject:` keyword and stay bound to that subject's
  directory. The shared `lora/consent.rb` gate requires action-scoped written
  subject permission and separate rights evidence for every local source set.
  MASTER has its own client
  and runtime policies; this one is STUDIO's.
- `lora/` — subject descriptors and private training plans. `bin/studio lora`
  runs a read-only validator. Merethe's preparation step builds in a private
  staging directory and preserves the last known-good dataset if a build fails.
  lora/judge.rb audits whole-frame texture, highlight, clipping and tonal-range proxies.
  Calibration requires at least five regular reference images outside the checkout;
  it prints path-free aggregate YAML by default, or writes a new mode-0600 file
  outside the checkout with --output. STUDIO_LORA_THRESHOLDS selects a private
  override. These proxies do not replace full-size human review or perceptual ΔE fixtures.
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

## Checks

`Rakefile` is the tree's check surface: `rake check` syntax-checks entrypoints
and audits the LoRA profiles, `rake test` runs the Dilla, Postpro motion,
Replicate, IdeaPicture, LoRA and private-preparation regressions, and `rake`
runs both. The test suite uses stubs and local temporary data; it does not need
a Replicate token or start paid training.

The FETAT writing project and its proposal moved to `BIZ/fetat/`; it was
writing output, not policy, and never part of this check surface.
