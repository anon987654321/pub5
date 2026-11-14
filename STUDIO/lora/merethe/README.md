# Merethe identity LoRA

This subject lives beside the other trained identities at `STUDIO/lora/merethe/`. Generated stills land directly in `STUDIO/lora/`; the subject directory holds private model setup, sources, data and weights.

## Privacy

The 15 recovered archive photographs and the 14 additional portraits currently
appear in the repository's existing Git history. New source copies, datasets,
weights, consent records and evidence are ignored by Git. Ignore rules do not
untrack existing files or remove earlier commits. Do not use \`git add -f\` for
photos, derived crops, dataset ZIPs, captions attached to private photos or
trained weights. Agreement to training is not blanket permission to publish
photographs or weights.

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

`sources/additional/` holds fourteen further portraits of Merethe grabbed from
her public site, https://www.tommervik.no. Each was selected with OpenCV YuNet
face detection and an SFace identity match against her own reference photos, so
every kept image has exactly one detected face that matches her; `SOURCES.md`
records the source URL and caption for each. Captions name the `MERETHE` trigger
and the pair `tommervik-NN.jpg` + `tommervik-NN.txt` is what the dataset builder
reads.

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

The preflight refuses fewer than 10 or more than 18 images, missing captions,
invalid caption triggers and missing/corrupt archived sources. It builds a
private ZIP only after these checks pass. The report is written to the ignored
\`.cache/prepare_report.json\`. The target is 12–18 images, in line with the
trainer's dataset guidance.

## Training plan — not executed

- Trainer: \`ostris/flux-dev-lora-trainer\`
- Pinned trainer version: \`26dce37af90b9d997eeb970d92e47de3064d46c300504ae376c75bef6a9022d2\`
- Trigger: \`MERETHE\`
- Initial steps: \`1600\`
- LoRA rank: \`16\`
- Destination: \`anon987654321/merethe-flux\` (the account's private model).
- Plan: \`train.yaml\`, mirroring the other subjects; 18 captioned images now
  build (\`prepare.rb\` reports \`READY_FOR_OPERATOR_REVIEW\`).

The version pin matches \`STUDIO/replicate/client.rb\`. The trainer README
recommends 12–18 varied subject images, caption sidecars, 1,000–3,000 steps and
rank 16–32; the plan is conservative. Reassess captions and sample outputs
before any second run.

Uploading the ZIP and starting paid training need a \`REPLICATE_API_TOKEN\` and
a separate explicit go-ahead. No provider call is made by \`prepare.rb\`.

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

Copy \`subject.env.example\` to the ignored local \`subject.env\` if you want
\`STUDIO/lora/photograph.rb --subject merethe\` to resolve the subject descriptor after
a private training manifest exists under \`weights/merethe/replicate_training.json\`.
Do not put API tokens in this file.
