# studio

**The media tools live here, each with one physical home and no second tree.**
studio holds Dilla, photograph and the Replicate client. master's runtime may
call into these tools through compatibility symlinks under `master/tools/`,
but the implementation is owned here.

## The tools

- `dilla/` — the Dilla engine. `dilla/dilla.rb` is the one Ruby source and
  `dilla/data/` carries its canonical music data (`dilla.json`,
  `music_theory.json`, `showcase.json`, `recovered_music.json`);
  `dilla/reference_analyzer.py` is the separate spectral-analysis process. Rendered output is replaceable:
  a new run may delete and replace it, and no rendered-sound default moves on
  one person's judgement.
- `photograph.rb` and `photograph/idea_picture.rb` — the image-generation
  entrypoint and its IdeaPicture implementation.
- `replicate/client.rb` — the Studio-owned Replicate provider client
  (`Studio::ReplicateClient`), with its own upload and download helpers.
  master has its own client and runtime policies; this one is studio's.

## Shared surfaces

- `output_paths.rb` — where generated output is allowed to land. The render
  directory is absolute and must not collide with the checkout.
- `subprocess.rb` — the one child-process helper the tools share.

## Checks

`Rakefile` is the tree's check surface: `rake check` loads every entrypoint
and proves the contracts answer, `rake test` runs `test/` (the Dilla and
IdeaPicture suites), and `rake` runs both. The suite runs without network
access and without the Replicate API.

## Writing projects

`docs/fetat/proposal.md` is the working master of the FETAT /
Familieetaten proposal — a consolidated document (source history,
evidence audit, implementation blueprint). It is writing output, not
policy, and not part of the check surface.


## pub5 port note

- One CLI: `bin/studio` dispatches to dilla, postpro, photograph, replicate
  and the test runner. No second entry surface.
- pub4's archaeology notes (`postpro/ARCHAEOLOGY.md`, `LEGACY_RESTORE.md`)
  were retired with the port; the render pipeline and its seed/version
  reproducibility guarantees are unchanged.
