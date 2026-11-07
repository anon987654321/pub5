# GLM handoff: local LoRA recovery and selfie refresh

**Target checkout:** `anon987654321/pub5`, branch `main`  
**Handoff prepared:** 2026-11-07  
**Source checkout:** local `pub4`, read-only  
**Starting pub5 revision:** `f5f10a22126bccd62cd11c78d120c6417de807e4`

## Mission

You have the operator's local shell and filesystem. Finish the local-only work needed to make the existing, approved LoRA checkpoints usable by the current pub5 selfie-series workflow, then generate ten materially different photographic selfies per eligible checkpoint if (and only if) the entire planned inference run fits the available Replicate budget.

Do not train new LoRAs. Do not publish photographs, datasets, captions, consent records, model weights, manifests or generated portraits. Do not make any commit to pub4. Do not push private media or local credentials to GitHub.

The user reported Replicate credit of USD 23.46 and OpenRouter credit of USD 0. OpenRouter is not needed for this task. Verify the available Replicate balance and current model pricing directly before inference; the reported balance is not a live billing guarantee.

## Immediate credential handling

Both API keys pasted into the ChatGPT conversation must be considered exposed. Revoke/rotate them before use. Never use the exposed values, copy them into this document, echo them in logs, put them in shell history, or write them into the repository.

Use only a newly rotated Replicate token supplied locally by the operator. `Studio::ReplicateClient` accepts `REPLICATE_API_TOKEN`, `REPLICATE_API_KEY`, a private `~/.config/replicate/config.json`, or the private `~/.config/master/env`. Prefer an environment variable entered with a silent prompt for this session, or the existing owner-only credential file. Never print the token.

Example interactive setup (the value is not echoed):

```zsh
read -s REPLICATE_API_TOKEN'?Rotated Replicate token: '
export REPLICATE_API_TOKEN
printf '\n'
```

At the end of the session, run `unset REPLICATE_API_TOKEN`. Do not copy credentials into `subject.env`, `consent.yml`, manifests, logs or receipts.

## Non-negotiable boundaries

1. Work in pub5 only. The local pub4 checkout is read-only input. Do not fetch, checkout, reset, clean, commit or push pub4.
2. Stay on pub5 `main`. Do not create branches, worktrees or GitHub Actions. Do not commit local private files.
3. Keep `sources/`, `dataset/`, `retouched/`, `weights/`, `out/`, `consent.yml`, `subject.env`, generated portraits and provider credentials local and private. Subject directories must be mode 0700; private files must be mode 0600.
4. Never restore Ragnhild's rejected older 40-image dataset, its retouched portraits or its old SDXL adapter. The pub4 notes record that she disliked that set and it was a poor likeness.
5. Never silently treat public availability of a photograph as a training licence. Confirm the rights holder's permission for model training and provider processing before using a source image.
6. No training, fine-tuning, dataset upload, publishing, sharing or model visibility changes. This task is inference using already-trained, pinned model versions only.
7. No destructive cleanup. Old renders are archived reversibly only by the selfie-series implementation, after a fully successful replacement. Ambiguous or unverifiable files stay untouched.
8. Do not mark any generated face as approved. The contact sheets and every render must remain pending human likeness review.

## Phase 1 — verify both local checkouts

From the pub5 checkout:

```zsh
pwd
git branch --show-current
git rev-parse HEAD
git status --short
test -d ../pub4/.git
git -C ../pub4 rev-parse --show-toplevel
git -C ../pub4 rev-parse HEAD
git -C ../pub4 status --short
```

If pub4 is not a sibling, locate the existing checkout and pass its exact path with `--from PATH`. Do not clone another copy or create a worktree. Record the two paths and revisions in your private run log. Confirm pub5 is on `main` and begin from the revision named above or a newer clean `main`.

Check the new local tools parse before using them:

```zsh
ruby -c STUDIO/replicate/lora/migrate_local.rb
ruby -c STUDIO/replicate/lora/merethe/prepare.rb
ruby -c STUDIO/photograph/selfie_series.rb
ruby -c STUDIO/photograph/idea_picture.rb
```

Run the STUDIO tests when the local gems are already available:

```zsh
cd STUDIO
rake test
cd ..
```

Do not install packages globally or change unrelated files just to make this task run. Report missing dependencies as blockers.

## Phase 2 — inventory local material before copying anything

Inspect the existing ignored/private paths in both checkouts. Use Ruby `Dir.glob` or a direct directory listing; do not use a broad recursive copy. Inventory only these subject paths:

- `STUDIO/replicate/lora/<subject>/`
- legacy `STUDIO/lora/<subject>/`
- legacy `studio/lora/training/<subject>/`

Subjects: `johann`, `merethe`, `ragnhild`.

For each subject, record whether the local directory has:
- `subject.env` (including `TRIGGER`, `DESCRIPTOR`, and `MODEL`);
- one or more exact `weights/<model>/replicate_training.json` manifests;
- source photographs and their captions;
- a completed, private `consent.yml`;
- any local checkpoint not represented by a pinned Replicate manifest.

Do not print image contents, credentials or consent evidence. Do not assume a weight file is a Replicate inference model. A valid inference manifest must contain a pinned `version` string in `owner/model:version` form.

## Phase 3 — consent and private destinations

Before any migration for a subject, create its destination directory under `STUDIO/replicate/lora/<subject>/` with mode 0700. Create `consent.yml` locally from `STUDIO/photograph/consent.example.yml`, set the correct subject slug, and chmod it to 0600.

The consent record must truthfully confirm:
- the subject's likeness-generation permission;
- provider-processing permission;
- the source-image rights holder's permission for generation/training use;
- provider-processing permission for those source images;
- concise evidence of the rights permission.

Do not infer any of these fields. The user's prior message confirms Merethe's consent to likeness generation and training, but rights to each photographer's images still need to be verified. Johann is the operator; use only his own source images or images he has rights to use. For Ragnhild, verify current permission directly from her; do not recycle the rejected set.

If a required fact or permission is not known, leave the corresponding consent field false and mark that subject blocked. Do not fabricate an evidence string just to pass validation.

## Phase 4 — dry-run and migrate approved private configuration

The migration utility defaults to dry-run and reads pub4 without modifying it:

```zsh
ruby STUDIO/replicate/lora/migrate_local.rb --from ../pub4
```

Use the exact pub4 path if not a sibling. If the full dry-run is blocked by a missing consent record, create/verify the record as above and rerun. Review every planned path before applying.

Apply only after the dry-run is understood:

```zsh
ruby STUDIO/replicate/lora/migrate_local.rb --from ../pub4 --apply
```

The default migration copies only `subject.env` and exact pinned
`weights/<model>/replicate_training.json` manifests. It does not import datasets, retouched photos, training worktrees or standalone safetensors. It refuses to overwrite destination files. If it reports a conflict, stop and compare both copies; do not delete either one.

For Johann, three original source photographs can be recovered from a known pub4 history commit. This is explicitly opt-in and writes to the private `sources/archive/` directory. First review its dry-run:

```zsh
ruby STUDIO/replicate/lora/migrate_local.rb \
  --from ../pub4 --subject johann --restore-johann-history
```

If and only if Johann's local consent/rights record is complete and the three files are wanted, apply:

```zsh
ruby STUDIO/replicate/lora/migrate_local.rb \
  --from ../pub4 --subject johann --restore-johann-history --apply
```

The three images are verified against their historical Git blob hashes. Their old captioned dataset images are not restored; old notes say those captions/data should be rebuilt from the operator's own reviewed photographs.

Use `--include-sources` only after inspecting the exact local source set and confirming rights for every file. Do not use it indiscriminately.

## Phase 5 — Merethe's archived originals

Pub4 history contains 15 images under the old `media/__lora/me2/` archive. The historic curation selected only `10.jpg`–`13.jpg` for general identity training. The other eleven were excluded for image quality, overlays, obscured faces or intimate/cropped framing. Do not add those eleven to a training dataset.

The recovery command now only recovers/verifies the originals locally; it does not prepare or replace a dataset:

```zsh
ruby STUDIO/replicate/lora/merethe/prepare.rb --recover
```

It verifies each original by Git blob SHA and writes to the ignored private `STUDIO/replicate/lora/merethe/sources/` folder. It makes no Replicate call.

Four clean images are not a training dataset. The old preparation plan requires at least six more distinct, rights-cleared, ordinary adult photographs with same-basename text captions containing the trigger `MERETHE`, preferably 12–18 total. Photos from tommervik.no or any other website may be considered as identity references only after verifying the actual photographer's licence/permission for provider processing and model-training use. Do not download or use web photos solely because they are publicly viewable.

Do not run the no-argument `prepare.rb` yet. It is a training-data preparation path, not required for the selfie inference run. If a complete, rights-cleared set is later ready, inspect and back up any existing local `dataset/` and `.cache/merethe_training.zip` first, then run preparation and review its report. `READY_FOR_OPERATOR_REVIEW` does not authorise an upload or training run. No training is part of this handoff.

## Phase 6 — Ragnhild's current model

Pub4's notes describe a separate newer seven-image FLUX model named
`anon987654321/ragnhild-flux`, but pub5 does not contain its private pinned
`replicate_training.json` manifest. Check the local pub4 checkout for a real
manifest first. If absent, use the rotated Replicate credential for read-only
model inspection and find the exact trained version that corresponds to the
approved current model.

Do not invent or guess a version hash. Do not silently substitute:
- the old `basicfeatures/ragnhild` adapter trained from the rejected photos;
- the old SDXL safetensors artifact;
- a newly trained model;
- the provider's mutable `latest` version when a pinned training version is required.

If the exact intended version cannot be confirmed, leave Ragnhild out of the paid run and report the blocker. Do not create a manifest with a made-up version.

## Phase 7 — validate the actual model set and estimate cost

The selfie-series command discovers every local
`STUDIO/replicate/lora/*/weights/*/replicate_training.json` manifest. Each model requires:
- a valid, private `subject.env`;
- a valid, private and subject-matched `consent.yml`;
- a private model directory and manifest;
- an exact, pinned `owner/model:version` value.

Inventory the exact model set with this read-only Ruby command:

```zsh
ruby -rjson -e '
  Dir.glob("STUDIO/replicate/lora/*/weights/*/replicate_training.json").sort.each do |path|
    parts = path.split(File::SEPARATOR)
    subject = parts[-4]
    model = parts[-2]
    begin
      version = JSON.parse(File.read(path)).fetch("version")
      puts [subject, model, version].join("\t")
    rescue StandardError => error
      warn "#{path}: #{error.class}: #{error.message}"
      exit 2
    end
  end
'
```

Check that every listed checkpoint is intended and is not the rejected old Ragnhild adapter. Do not add a manifest simply to make a subject appear.

The series makes **10 paid predictions per discovered manifest**. It does not currently have an in-command billing cap. Before the first prediction:
1. Verify the live available Replicate balance in the account.
2. Look up the current inference price for every exact pinned model/version, not a generic base-model estimate.
3. Calculate the full run estimate: 10 × each eligible checkpoint's per-image estimate, plus any provider-specific charges or possible retries.
4. Keep a USD 3.46 reserve against the user's reported USD 23.46 balance. Do not start unless the full expected run is at or below USD 20.00 and the live balance is sufficient.
5. If the endpoint price is not visible or cannot be estimated responsibly, stop before any prediction and report the unknown. Do not use the entire account balance as a guess.

There is no training spend in this task. Do not call the training endpoint, upload a dataset ZIP, or create a destination model.

## Phase 8 — run ten distinct selfies per eligible checkpoint

Only after all preflights pass and the total estimate is inside the spending ceiling, run from the pub5 root:

```zsh
ruby STUDIO/photograph.rb --selfie-series
```

The ten shot directions are deliberately different:
1. morning window / Portra-style color negative;
2. direct-flash indoor mirror snapshot;
3. rainy neon city street at night;
4. windy Nordic fjord under overcast light;
5. golden-hour backlight;
6. tungsten café candid;
7. Tri-X-inspired black-and-white sidewalk portrait;
8. fluorescent train or tram at night;
9. bright summer coastal Ektar-style color;
10. low-key editorial corridor.

Each uses a distinct seed and prompt. The existing `IdeaPicture` path pins the exact manifest version, generates one still, then runs Postpro. Postpro now applies an independent mandatory analog finishing-grain layer even if the creative recipe already contains grain. Do not bypass Postpro or remove its sidecars.

Outputs are written outside the checkout under
`~/ideas/selfie-series-<run-id>/<subject>/<model>/`. The contact sheet and
manifest stay private. The command authenticates with a read-only catalogue
request before inference. It archives verified prior render families only
after every registered model has all ten new renders verified. If the run is
partial or blocked, it must leave the prior deliverables in place. Unverified
legacy files are preserved and reported, never deleted.

Watch the provider responses, actual charge/billing telemetry if provided,
and output count throughout the run. If errors or provider charges indicate the
budget could be exceeded, stop rather than retrying blindly. Preserve partial
outputs and report the exact count; do not label the series complete.

## Phase 9 — inspect and report

For every eligible model, verify:
- exactly ten output images and ten source renders;
- all output images open successfully and have corresponding Postpro sidecars;
- sidecars identify the finishing-grain pass;
- source/output SHA-256 values match the private series manifest;
- contact sheet contains ten entries and says **PENDING OPERATOR REVIEW**;
- every model and render remains `pending_operator_review`;
- old managed renders were archived only when the replacement was fully complete;
- ambiguous or unrelated files remain untouched.

Open the contact sheets for visual inspection, but do not approve, publish, send,
or use an image externally. Likeness and quality acceptance belongs to the
operator and the person depicted. A manifest `status: complete` means only
that ten files were generated for each model.

Report back with:
- pub5 revision and pub4 source revision;
- each subject/model and pinned version used (no tokens);
- how many original source files were recovered locally;
- which subjects were blocked and why;
- number of successful/failed predictions;
- actual spend shown by Replicate, plus the remaining balance if visible;
- output directory and manifest path;
- contact-sheet paths;
- retirement report and any preserved ambiguous files;
- test commands and real exit codes.

Do not attach face photographs to GitHub issues or commit them. Do not write
private photo paths, consent evidence or personal data into the public README.
Keep the final local report concise and redact credentials.

## Stop conditions

Stop before paid inference if any of the following applies:
- a credential has not been rotated after its exposure;
- subject consent, source rights or provider-processing permission is missing;
- a source image's rights are uncertain;
- a model manifest is missing, malformed, mutable/unpinned or points to an unintended adapter;
- Ragnhild's exact approved current model version cannot be confirmed;
- the complete estimate exceeds USD 20.00, the live balance is insufficient, or price is opaque;
- Postpro fails, the finishing-grain sidecar is missing, or image verification fails;
- the local working tree is not the expected pub5 checkout.

A blocked subject does not block other subjects with complete independent
preflights, but never weaken the requirements to increase the number of models.
