# Merethe identity LoRA

This subject lives beside the other trained identities at `STUDIO/lora/merethe/`. Generated stills land directly in `STUDIO/lora/`; the subject directory holds private model setup, sources, data and weights.

## Privacy

The 15 recovered archive photographs, 14 additional portraits, their 14
training-caption sidecars and the three tracked subject descriptors have been
removed from the current public default-branch tree. Earlier pub5 commits and
the archived pub4 source commit remain reachable until a separate coordinated
history cleanup. Source copies, captions, datasets, weights, subject.env,
consent records and evidence are local-only. Ignore rules do not erase history.
Do not force-add private media or subject configuration. Agreement to training
is not blanket permission to publish photographs or weights.

This package does not upload images, create a Replicate training, or generate
images. Those are separate operator actions. Keep the destination model private
unless the subject separately agrees to publication and distribution.

## Consent and source rights

Likeness generation and each Replicate image upload require a private
`consent.yml` with written subject permission for `likeness_generation` and
`provider_processing`. Dataset preparation additionally requires explicit
`model_training` and `model_retention` permission, plus `training_use` rights
for every source set. Merethe's source evidence must cover `me2_archive` and
`additional_images`; ZIP upload and model training additionally require a
separate `training_dataset` rights entry. Model publication and distribution
are independent permissions and default to false.

Copy `STUDIO/lora/consent.example.yml` to the local
`STUDIO/lora/merethe/consent.yml`. Record written subject permission in a
private file under `evidence/`; use separate rights evidence for each source
set. A public webpage is provenance, not permission to train or send
photographs to a provider. The evidence directory must be mode 0700 and each
record mode 0600. The gate reads but never creates or infers permission.

The repository ignores new subject data, but the existing source photographs
remain in Git history. Ignore rules do not untrack files or erase earlier
commits. Repository visibility and history cleanup remain separate operator
actions.

## Additional portraits

The previous public source copies, per-image captions and face-match notes
have been removed from this tree. Any future material must be supplied and
reviewed locally, with written subject permission and separate photographer or
source-rights evidence before generation, provider processing or training. A
public webpage URL is provenance, not permission. Keep approved local material
under `sources/additional/`; each image needs a same-basename `.txt` caption
containing the `MERETHE` trigger.

## Recover and prepare

From the repository root:

\`\`\`sh
ruby STUDIO/lora/merethe/prepare.rb --recover
\`\`\`

This downloads the 15 historical originals from commit
\`8e1955ae130592ab7c20ee266c024f061431c67e\` into the ignored local \`sources/\`
folder and verifies every file against its original Git blob SHA-1. Originals
are not modified.

The first face-led curation contains only \`10.jpg\` through \`13.jpg\`. The other
archived frames remain available in \`sources/\` but are not placed in the general
identity dataset by default: some are low-resolution, overlaid with text or
stickers, lack a visible face, or use intimate/cropped framing. In particular,
this avoids teaching a general-purpose identity model from intimate images.

Four clean portraits are not enough for a reliable first training. Add at least
six more suitable photos (eight to fourteen is better) to the local, ignored
folder \`STUDIO/lora/merethe/sources/additional/\`. Prefer ordinary,
non-intimate photos with her face clearly visible, varied expressions, angles,
clothing and everyday settings. Avoid filters, stickers, text overlays, heavy
retouching and repeated near-duplicates. Each image needs a same-basename \`.txt\`
caption in that folder, and the caption must include the trigger word \`MERETHE\`.

Example pair:

\`\`\`text
sources/additional/photo-01.jpg
sources/additional/photo-01.txt
\`\`\`

After adding and reviewing the images, run:

\`\`\`sh
ruby STUDIO/lora/merethe/prepare.rb
\`\`\`

The preflight refuses fewer than 12 or more than 18 images, missing captions,
invalid caption triggers and missing/corrupt archived sources. It builds a
private ZIP only after these checks pass. Each previous prepared dataset and
training ZIP is retained under the ignored .cache/prepared-archive-* folder
before a new pair is published; an interrupted publication leaves its staging
files in place and reports their recovery path. The report is written to the ignored
\`.cache/prepare_report.json\`. The target is 12–18 images, in line with the
trainer's dataset guidance.

## Training plan — shared with Johann and Ragnhild

All three identities use one Replicate trainer and one canonical contract:

- Trainer: `replicate/fast-flux-trainer`
- Immutable trainer version: `080f17375c73ef43e1009da9d560ab5f935176c61a0c7a88866c8b8387057675`
- Trigger: `MERETHE`
- Training type: `subject`
- Training steps: `1000`
- Seed: `42`
- Dataset: 12–18 varied, captioned, private photographs around 1024px
- Destination: `REPLICATE_DESTINATION` in the local, owner-only `subject.env`

The exact contract lives in `STUDIO/lora/training_standards.yml`. The same
file supplies the Replicate request, dataset-size bounds and inference defaults.
The validator checks the local plan, trigger, captions, filesystem permissions,
consent and source-rights records before training is eligible.

After the approved dataset is ready, run all three jobs together from the
repository root:

```sh
ruby STUDIO/lora/validate.rb --json
ruby STUDIO/lora/train.rb --all
```

The runner preflights all three subjects before the first upload, verifies every
destination is private, and records each successful result as
`TRAINED_NEEDS_LIKENESS_REVIEW`. It does not mark the new model as approved.

Generate three private candidate portraits for each subject and compare them
against the original source photographs:

```sh
ruby STUDIO/lora/review.rb --subject merethe --candidate
```

The private contact sheet and report are written below
`STUDIO/lora/merethe/.cache/likeness-review/`. Repeat for Johann and Ragnhild.
Only after the person is recognisable in every candidate should the exact
immutable model version be entered in that subject's local
`subject.env` as `LIKELINESS_REVIEWED_VERSION`.

The six-image final batch is a separate operation. Selfie generation is
append-only: no prior portrait, graded still, film or sidecar is replaced or
deleted. Compare each new series with the previous one in the private gallery.

## Promo video

Once the LoRA renders a selfie series, cut it into the piece the subject
watches:

\`\`\`sh
ruby STUDIO/dilla/dilla.rb industrial-techno --bars 8 --out dilla.wav
ruby STUDIO/promo.rb --subject merethe --audio dilla.wav --out merethe-promo.mp4
\`\`\`

\`promo.rb\` pushes each still, crossfades them, lays the \`dilla_heavy\` film
look over the whole piece and sets the dilla render underneath; it writes
\`merethe-promo.mp4\` and a \`.promo.json\` sidecar. This is the assembly step
after generation and training, not a substitute for either.

## Subject environment

Copy \`STUDIO/lora/subject.env.example\` to the ignored local
\`STUDIO/lora/merethe/subject.env\` when private subject configuration is
needed. Keep the descriptor and model settings outside Git. A private training
manifest may live under \`weights/merethe/replicate_training.json\`.
Do not put API tokens in this file.
