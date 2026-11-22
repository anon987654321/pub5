# Selfie/LoRA lane — blocker removal receipt (2026-11-22)

Sandbox recycle wiped `pub5/` and `pub/` to empty shells. Everything
restorable has been restored and proved with the repo's own gate code and test
suite. Two items remain that only the operator can provide; nothing was
fabricated, and the consent gate was never bypassed.

## Blockers removed

| # | Blocker | Fix |
|---|---|---|
| 1 | `pub5` working tree + git dir wiped | Re-cloned sparse blobless at HEAD `541b6494`; `STUDIO/lora`, `STUDIO/replicate`, `STUDIO/postpro`, `STUDIO/dilla`, `MASTER/data|bin|lib` materialized |
| 2 | Three private `subject.env` descriptors lost | Recovered from git history (parent of removal commit `33adb91d`), updated to the current contract (`REPLICATE_DESTINATION` + versioned `REPLICATE_MODEL`), written 0600 into 0700 subject dirs; gitignored, stay local |
| 3 | Root `.gitignore` not materialized by sparse checkout (privacy armor absent; `lora_consent_test` failed) | Restored from `HEAD:.gitignore` (399 lines); all 11 probe paths now correctly ignored |
| 4 | Ruby toolchain | Verified 3.3.13 via `tools/ruby/ruby` |
| 5 | `libvips` + `ruby-vips` missing (review lane unrunnable) | Extracted `libvips42t64` + `libcgif0`, `libmatio13`, `libspng0` into `tools/ruby/libvips`; installed `ruby-vips` 2.3.0; wrapper carries `LD_LIBRARY_PATH`; `lora_review_test` 7/7 |
| 6 | Model pins | johann + ragnhild: exact immutable pins from tracked private manifests mirrored into `subject.env`. Validator states: **johann PASS, ragnhild PASS**, merethe FAIL (see below) |

## Proof

Test suite (`STUDIO/replicate/test`, this tree, this Ruby):

```
consent_enforcement 4/0   lora_consent 9/0   idea_picture 41/0
selfie_series 14/0        merethe_lora 11/0  lora_craft 3/0
lora_cli 9/0              lora_migrate_local 7/0   lora_review 7/0
lora_profiles 15 runs, 1 failure (merethe version pin — truthful)
lora_judge 10 runs, 10 skips (graceful)
```

Preflight receipt (repo's own `Consent.validate` + `validate_model!` + token
loader): [PREFLIGHT_RECEIPT.json](PREFLIGHT_RECEIPT.json). Re-run anytime:

```
cd pub5 && /home/z/my-project/tools/ruby/ruby /home/z/my-project/scripts/lora_preflight.rb
```

For every subject the consent gate reports exactly one error —
`private consent.yml is missing` — which is the proof that everything in
front of it (env format, permissions, model pins) now passes the real gate
code.

## Update 2026-11-22 (later session): token resolved, provider measured

1. **`REPLICATE_API_TOKEN` — RESOLVED.** The operator supplied the key; it now
   lives in `~/.config/master/env` (0600, dirs 0700), the client's own designed
   source. `provider_metadata_check.json` (metadata-only calls: schema reads
   and model GETs, no images, no likeness processing) measured with it:

   | subject | model exists | schema inputs | latest version |
   |---|---|---|---|
   | johann | yes | 21 | `c2a1755b…` — identical to the tracked pin |
   | ragnhild | yes | 21 | `ae6785fe…` (the Oct-10 overfit; tracked pin is deliberately the Sep-15 `1f868a15…`) |
   | merethe | **no — Replicate 404 Model not found** | — | — |

2. **Remaining blocker — private consent records only.** `consent.yml` +
   `evidence/` per subject were never tracked (by design) and died with the old
   working tree. Recreate each from `STUDIO/lora/consent.example.yml` with
   `likeness_generation` + `provider_processing` true for generation, evidence
   files 0600 inside the subject's `evidence/`, subject dir 0700. The gate
   validates, never infers; these cannot be reconstructed by an agent.

## Designed flow once consent records land

```
ruby STUDIO/lora/review.rb --subject johann --candidate     # 3 private candidates into .cache/likeness-review
# compare contact sheet vs approved references — verdict is human, not automated
# then set LIKELINESS_REVIEWED_VERSION=<exact version> in that subject's subject.env
ruby STUDIO/lora/generate_selfies.rb                        # --all-subjects --count 4 through the photograph lane
```

Johann and ragnhild are render-ready the moment their consent records exist
(trained models verified live; ragnhild's pinned version is the Sep-15
weights, not the overfit latest). Merethe is blocked at the training lane:
`anon987654321/merethe-flux` returns 404 (never trained or deleted), so it
needs the consent-gated dataset preparation (`prepare.rb`, digest-verified
ME2 recovery) and a fast-flux training run before any likeness work — and its
`LIKELINESS_REVIEWED_VERSION` pin can only be set after that model exists and
the review lane passes on it.
