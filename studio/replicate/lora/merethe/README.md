# Merethe identity LoRA preparation

This is the first isolated STUDIO migration slice in pub5. The planned owner is
\`studio/\` (lowercase, as declared in PLAN.md); the existing Replicate client
and photograph renderer have not yet been ported here. This package therefore
prepares and verifies a private dataset. It does not start training or generate
images.

## Privacy boundary

Source photos, captions, curated datasets, weights, output and ZIP files are
excluded by the root \`.gitignore\`. They are local working material, not
repository assets. Do not use \`git add -f\` for any of them. Consent to train
does not by itself mean consent to publish photographs, captions, model weights
or generated images. Keep the resulting model private unless Merethe separately
agrees to sharing it.

## Recover the original archive

From the repository root:

\`\`\`sh
ruby studio/replicate/lora/merethe/prepare.rb --recover
\`\`\`

The source is pinned to the immutable pub4 archival commit
\`8e1955ae130592ab7c20ee266c024f061431c67e\`. pub4 is read-only; no workflow in
this package writes to it. The script retrieves all 15 originals into the
ignored local \`sources/\` folder and verifies each against its historical Git
blob SHA-1 before keeping it.

## Curate the training set

The initial face-led selection is \`10.jpg\` through \`13.jpg\`. The other archived
photos remain in private \`sources/\` for operator review; they are excluded from
the initial identity dataset because some lack a clear face, contain overlays,
or use intimate/cropped framing. Do not include intimate images in a general
identity model.

Four portraits are not enough for a robust first training. Add at least six
more ordinary, non-intimate photographs to:

\`\`\`text
studio/replicate/lora/merethe/sources/additional/
\`\`\`

For each image, add a same-basename \`.txt\` caption. Use varied angles, light,
expressions, clothing and everyday settings. Avoid filters, stickers, text,
heavy retouching and near-duplicates. Each caption must include the trigger
word \`MERETHE\`.

Example:

\`\`\`text
sources/additional/photo-01.jpg
sources/additional/photo-01.txt
\`\`\`

Then run:

\`\`\`sh
ruby studio/replicate/lora/merethe/prepare.rb
\`\`\`

The preflight accepts 10–18 images, requires readable image signatures and a
caption for each added image, and writes a ZIP only when the selected archive
photos are present and all checks pass. The range is this package's initial
curation limit, not a claim about a provider's universal limits. The report is
written to ignored \`.cache/prepare_report.json\`. The ZIP and intermediate
dataset are private, mode-restricted local files.

## Training plan — not executed

- Trainer: \`ostris/flux-dev-lora-trainer\`
- Pinned trainer version: \`26dce37af90b9d997eeb970d92e47de3064d46c300504ae376c75bef6a9022d2\`
- Trigger word: \`MERETHE\`
- Initial steps: \`1000\`
- LoRA rank: \`16\`
- Destination: an operator-selected private Replicate model

The trainer pin and starting settings were carried from the pub4 Replicate
client. The training package still needs to be integrated with pub5's STUDIO
provider client when that runtime is ported. No Replicate API call is made by
\`prepare.rb\`; uploading and paid training require a separate explicit action.
