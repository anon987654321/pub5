# STUDIO

**The media tools live here, each with one physical home and no second tree.**
STUDIO holds Dilla, photograph and the Replicate client. MASTER's runtime may
call into these tools through compatibility symlinks under `MASTER/tools/`,
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
- `photograph/reference_picture.rb` — an additive, consent- and source-rights-gated reference route using Qwen-Image-Edit-2511. It is separate from the trained-LoRA route and does not create embeddings or train weights.
- `photograph/lookbook.yml` and `photograph/LOOKBOOK.md` — the shared shot/lighting/color/film/VFX prompt profiles and their research notes.
- `photograph/consent.example.yml` — a local-only consent and source-rights template. Completed per-subject `consent.yml` files are ignored by Git.
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

## Reference-guided portraits

The existing `ruby STUDIO/photograph.rb PROMPT` path remains the trained-LoRA
route. The new route is explicit:

```sh
ruby STUDIO/photograph.rb --reference \\
  --subject merethe \\
  --reference-image front.jpg \\
  --reference-image three-quarter.jpg \\
  --reference-image expression.jpg \\
  --look natural_selfie --seed 42 --cost-limit-usd 0.03 \\
  "A relaxed phone selfie outdoors in soft daylight"
```

Place source files in `STUDIO/replicate/lora/<subject>/sources/`. Before any
upload, the route verifies image format, size, distinct content, subject scope,
a private `consent.yml` and evidence that both likeness generation and the
source-image rights/provider-processing permissions are confirmed. Copy
`photograph/consent.example.yml` to the subject's private folder, complete it,
and set mode 0600. The completed consent file, sources and outputs must never
be committed. The output and its JSON receipt are written outside the checkout
with owner-only permissions.

The one-image cost estimate is USD 0.03 as reviewed 2026-11-07. The CLI
requires an explicit estimate limit. This is a preflight estimate, not a
provider-enforced billing cap; confirm the current model price and terms before
each paid run. No reference image is uploaded and no charge is made by
preflight. The route does not train a LoRA, create face embeddings, publish
images, or change the existing trained-model route.

The lookbook is a creative starting point, not a substitute for visual
approval. Read `photograph/LOOKBOOK.md` for cinematography, film response,
color management, diffusion and VFX guidance.

## Writing projects

`docs/fetat/proposal.md` is the working master of the FETAT /
Familieetaten proposal — a consolidated document (source history,
evidence audit, implementation blueprint). It is writing output, not
policy, and not part of the check surface.
