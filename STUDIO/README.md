# STUDIO

**The media tools live here, each with one physical home and no second tree.**
STUDIO holds Dilla, photograph and the Replicate client. MASTER's runtime may
call into these tools through compatibility symlinks under `MASTER/tools/`,
but the implementation is owned here.

## The tools

- `dilla/` — the Ruby-only music engine, canonical music data, dependency-free
  spectral reference analyzer, and Ableton Live Set recovery tools. The renderer
  remains owned by `dilla/dilla.rb`; the stdlib-only `dilla/lib/als*.rb` tools
  recover composition archives and MIDI from `.als` files. The unified
  `bin/studio` CLI exposes `dilla`, `postpro` and `ableton inventory|export|midi`.
  Rendered output is replaceable:
  a new run may delete and replace it, and no rendered-sound default moves on
  one person's judgement.
- `rg69.html`, `rg69.css` and `rg69.js` — the RG-69 browser beat machine. Its page, styles and application code are separate assets under MASTER's HTML Laws; Tone.js 14.8.49 is loaded from a version-pinned CDN and failure is reported visibly.
- `photograph.rb` and `photograph/idea_picture.rb` — the image-generation
  entrypoint and its IdeaPicture implementation.
- `replicate/client.rb` — the Studio-owned Replicate provider client
  (`Studio::ReplicateClient`), with its own upload and download helpers.
  MASTER has its own client and runtime policies; this one is STUDIO's.

## Shared surfaces

- `output_paths.rb` — where generated output is allowed to land. The render
  directory is absolute and must not collide with the checkout.
- `subprocess.rb` — the one child-process helper the tools share.

## Checks

`Rakefile` is the tree's check surface: `rake check` loads every entrypoint
and proves the contracts answer, `rake test` runs `test/` (the Dilla and
IdeaPicture suites), and `rake` runs both. The suite runs without network
access and without the Replicate API.

The FETAT writing project and its proposal moved to `BIZ/fetat/`; it was
writing output, not policy, and never part of this check surface.
