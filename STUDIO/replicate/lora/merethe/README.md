# Merethe source preparation

Merethe's historical source archive lives in the old pub4 commit
`8e1955ae130592ab7c20ee266c024f061431c67e`. The preparation script recovers
all 15 originals into this local, ignored directory and verifies each Git blob
hash. It does not write the images to pub5 or upload them to a provider.

The historical curation selected only `10.jpg` through `13.jpg` for a
general identity dataset. The other images are kept as recoverable originals
but excluded from that dataset because of low resolution, overlays, obscured
faces or intimate/cropped framing.

Before preparing a training archive, create
`STUDIO/replicate/lora/merethe/consent.yml` from
`STUDIO/photograph/consent.example.yml`, set its subject to `merethe`, verify
both likeness/provider consent and source-image rights, and set mode 0600.
The preparation command now refuses to build a dataset without that record.

```sh
ruby STUDIO/replicate/lora/merethe/prepare.rb --recover
```

The recovery downloads the old originals locally. Preparation remains blocked
until the private consent record exists and at least ten suitable images are
available. Four selected archive portraits are only a starting subset: add at
least six more distinct, rights-cleared adult photographs with captions that
include `MERETHE` under `sources/additional/`. Do not add website photographs
merely because they are publicly viewable; verify the photographer's licence
or obtain permission for model training and provider processing first.

When the preparation report says `READY_FOR_OPERATOR_REVIEW`, inspect the
dataset and captions before any separate explicit decision to upload or train.
This script never calls Replicate and never starts training.
