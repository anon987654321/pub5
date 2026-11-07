# Merethe identity LoRA preparation

This is a limited STUDIO migration slice in pub5's planned lowercase \`studio/\`
tree. The STUDIO runtime, Replicate client and photograph renderer have not yet
been ported; the subject-preparation library is therefore not exposed through
\`bin/master\` yet. It is ready to be wired into that phase without introducing
a second filesystem or HTTP implementation.

## Privacy boundary

Source photos, captions, curated datasets, weights, outputs and ZIP bundles are
excluded by the root \`.gitignore\`. They remain local operator material. Do not
use \`git add -f\` for them. Consent to train does not itself mean consent to
publish photographs, captions, model weights or generated images. Keep the
resulting model private unless Merethe separately agrees to sharing it.

All external effects go through the injected \`Core::World\`: archive downloads
use \`world.net\`, local reads and writes use \`world.read\` / \`world.write\`, and
ZIP creation uses \`world.exec\`. The capability declaration is
\`studio/manifest.yml\`. This library makes no Replicate upload, training or
image-generation call.

## Historical source set

The immutable, read-only source is pub4 archival commit
\`8e1955ae130592ab7c20ee266c024f061431c67e\`, at
\`media/__lora/me2/01.jpg\` through \`15.jpg\`. Recovery verifies each file
against its original Git blob SHA-1 before writing it to the ignored local
\`studio/replicate/lora/merethe/sources/\` directory. pub4 remains read-only;
the recovery endpoint is the only reference to it.

The initial face-led selection is \`10.jpg\` through \`13.jpg\`. The other
originals are retained locally for review but excluded from the initial
identity dataset because some lack a clear face, contain overlays, or use
intimate/cropped framing. Do not include intimate images in a general identity
model.

## Additional photos

Four portraits are not enough for a robust first training. Add at least six
more ordinary, non-intimate photographs to the ignored local directory:

\`\`\`text
studio/replicate/lora/merethe/sources/additional/
\`\`\`

Create the ignored local manifest
\`studio/replicate/lora/merethe/sources/additional.json\` as a JSON array:

\`\`\`json
[
  {
    "file": "photo-01.jpg",
    "caption": "MERETHE, an everyday portrait in soft window light."
  }
]
\`\`\`

Use varied angles, expressions, clothing, light and ordinary settings. Avoid
filters, stickers, text overlays, heavy retouching and near-duplicates. Each
image must have a same-name record in the manifest, a supported image
signature, and a caption containing the trigger word \`MERETHE\`. The initial
preflight range is 10–18 images; 12–18 is the intended target for this first
pass.

## Preparation contract

The future STUDIO command adapter calls:

- \`Studio::MeretheLora.recover!(world:)\` to retrieve and verify the historical
  originals.
- \`Studio::MeretheLora.prepare!(world:)\` to validate the four selected archive
  photos and the additional manifest, then create a private fingerprinted
  dataset and ZIP.

The report is written to ignored
\`studio/replicate/lora/merethe/.cache/prepare_report.json\`. A non-ready state
is reported as \`BLOCKED\`; a ZIP is produced only after all preflight checks
pass. The dataset fingerprint keeps separate inputs in separate output paths.

## Training plan — not executed

- Trainer: \`ostris/flux-dev-lora-trainer\`
- Pinned trainer version: \`26dce37af90b9d997eeb970d92e47de3064d46c300504ae376c75bef6a9022d2\`
- Trigger word: \`MERETHE\`
- Initial steps: \`1000\`
- LoRA rank: \`16\`
- Destination: an operator-selected private Replicate model

The trainer pin and starting settings were carried from the pub4 Replicate
client. The training adapter must be integrated with pub5's provider client
when the STUDIO runtime is ported. Uploading and paid training require a
separate explicit action; neither is part of this preparation package.
