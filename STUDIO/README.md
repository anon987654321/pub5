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
  `bin/studio` CLI exposes `dilla`, `postpro`, `lora` validation and
  `ableton inventory|export|midi`.
  Rendered output is replaceable:
  a new run may delete and replace it, and no rendered-sound default moves on
  one person's judgement.
- `rg69.html`, `rg69.css` and `rg69.js` — the RG-69 browser beat machine. Its page, styles and application code are separate assets under MASTER's HTML Laws; Tone.js 14.8.49 is loaded from a version-pinned CDN and failure is reported visibly.
- `photograph.rb` and `photograph/idea_picture.rb` — the image-generation
  entrypoint and its IdeaPicture implementation.
- `replicate/client.rb` — the Studio-owned Replicate provider client
  (`Studio::ReplicateClient`), with version-aware input-schema reads, bounded
  transfers and explicit provider errors. `train_lora`, `upload_file` and
  `upload_zip` require a `subject:` keyword and validate the private consent
  record before any provider schema, model-creation, upload or training request.
  MASTER has its own client and runtime policies; this one is STUDIO's.
- `lora/` — subject descriptors and private training plans. `bin/studio lora`
  runs a read-only validator; `lora/consent.rb` is the shared gate for source
  recovery, dataset preparation and likeness generation. It requires separate
  written subject-consent and per-source rights evidence under the ignored
  private `evidence/` directory. Merethe's preparation step builds in a private
  staging directory and preserves the last known-good dataset if a build fails.

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
