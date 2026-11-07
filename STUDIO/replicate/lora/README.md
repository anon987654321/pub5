# Private LoRA subject inventory

This directory is the canonical STUDIO home for local subject inputs and
pinned Replicate inference manifests. The private parts are deliberately not
tracked: photographs, weights, model manifests, subject descriptors and
consent records remain on the operator's machine.

## Bring forward local material

From the pub5 checkout, the migration tool reads a neighbouring pub4 checkout
without modifying it. It starts in dry-run mode:

```sh
ruby STUDIO/replicate/lora/migrate_local.rb --from ../pub4
```

It copies only `subject.env` and exact
`weights/<model>/replicate_training.json` manifests by default. Add
`--include-sources` only after reviewing the source set. For Johann, the
explicit `--restore-johann-history` option recovers three verified source
originals from a known pub4 commit into private `sources/archive/`; it does
not restore the old training dataset or captions. It never copies historical
training datasets, retouched portraits, training worktrees or standalone
safetensors. It never overwrites a destination file.

Before applying, create a private consent record for each subject from
`STUDIO/photograph/consent.example.yml`, set the subject slug, verify the
likeness and provider-processing permission, and document source-image rights.
Set mode 0600. Then run the same command with `--apply`. The tool still
requires a valid destination consent record before copying anything.

The private directories are ignored by Git. Do not force-add face images,
datasets, manifests, checkpoints, consent records or credentials.

## What the repository history actually contains

- **Merethe:** pub4 contains a 15-image historical archive under
  `media/__lora/me2/`. Only four were selected in the old curation guide as
  clean identity portraits. The other eleven were excluded for quality,
  framing, overlays or intimate/cropped content. Recovery is implemented in
  `merethe/prepare.rb`; preparation now requires a valid private consent and
  source-rights record. The four selected images are not a sufficient training
  set: the guide calls for at least six additional suitable, rights-cleared
  photographs before a training ZIP can be prepared. No Merethe LoRA training
  was recorded as completed.

- **Johann:** pub4 history briefly contained three captioned dataset images
  and three source images, then removed them from the public tree. The retained
  note says the dataset must be rebuilt locally from the operator's own
  photographs. Three images are not a training set; use a curated 12–18 image
  collection and a valid local Replicate version manifest before the selfie
  series can include Johann.

- **Ragnhild:** the 40-image older set was removed after she disliked it and
  it failed as a likeness. This migration intentionally does not recover or
  reuse that set. A later pub4 note describes a separate seven-image trained
  FLUX model, `anon987654321/ragnhild-flux`, but pub5 does not contain its
  private pinned `replicate_training.json` manifest. The old SDXL safetensors
  artifact is not a substitute for a pinned Replicate version and is not
  imported. Recover the current approved model manifest from the private
  provider account, then verify consent and source rights locally.

## Run the selfie comparison

The current renderer discovers only valid local
`<subject>/weights/<model>/replicate_training.json` manifests. It creates ten
distinct photographic directions per discovered model and marks every render
pending human review. A series marked complete means all files rendered; it
does not mean the subject has approved the likeness.

```sh
ruby STUDIO/photograph.rb --selfie-series
```

No provider request is made by the migration tool. Selfie generation is a
separate paid Replicate action.
