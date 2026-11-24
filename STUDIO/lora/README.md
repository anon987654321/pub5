# LoRA and subject photography

This project owns subject-aware training, inference, evaluation and photography workflows. Each subject's datasets, consent evidence, model versions and likeness reviews remain separately scoped. Private media and credentials do not belong in the public repository unless the operator records explicit publication approval; the 2026-11-24 approval in Privacy covers only the files named there.



## What makes a photograph good

> Recovered provenance: this document was written against pub4 (2026-08-25,
> preserved at pub4@5c1529710, read-only) and restored into pub5 because
> `STUDIO/lora/guides.yml` cites it as its source. The body below is verbatim
> as recovered. Where the body names pub4-era state, the pub5 mapping is:
> the four layers are runtime data in `STUDIO/lora/guides.yml` (`layers:`),
> the house grade default lives in `../postpro/postpro.rb` and
> `../postpro/lib/presets.rb`, and §4's uncanny metrics are measured by
> `../postpro/uncanny.rb` with its ratchet. MASTER's rule file in this
> repository is `MASTER/data/laws.yml`; the refit section below keeps the
> historical wording. The repligen chain engine did not migrate; the
> generation lane is `./` with `../replicate/client.rb`.

Research note, 2026-08-25. Written because three STUDIO tools now depend on the
answer and none of them had it written down: **lora** decides what a dataset
should contain, **repligen** decides what to ask a model for, and **postpro**
decides what to do to the result.

The useful finding is that these four layers fail independently, and only one of
them is postpro's to fix. Knowing which is which is the difference between
grading a photograph and trying to grade a mistake.

## 1. Geometry — decided before anything else, and postpro cannot touch it

**Focal length does not distort a face. Distance does.** An 85mm lens is not
flattering because of the glass; it is flattering because you have to stand
2–3 m away to fill the frame with a head, and at that distance the nose is not
meaningfully closer to the sensor than the ears. At 40 cm it is, by a large
proportion, and the nose enlarges while the ears recede.

This is why portrait photographers work at 85–135mm, and why 135mm reads as
flatter still: the working distance grows to 3–5 m.

**And it is exactly why selfies look like selfies.** A selfie is an arm's
length. The geometry is fixed by anatomy at roughly 40–70 cm, which is the
distortion range. No lighting, no grade and no retouch removes it, because it
is a projection, not a rendering.

**The opportunity that only exists in generation.** A generated image has no
real camera in it. It can be asked for the *geometry* of a 3 m portrait while
keeping the *framing and gaze* of a selfie — held eye contact, intimate crop,
casual setting. Those two have never been available at once, because in the
physical world the framing implies the distance. This is the single most
specific thing to ask a model for, and it is invisible if you prompt for
"selfie" and let the model reproduce the distortion it learned from millions of
real ones.

Ask for the distance, not the lens.

## 2. Light — shape it at capture; postpro can grade it, not move it

The classical patterns, and what each does to a face:

| pattern | key light | effect |
|---|---|---|
| **butterfly** (Paramount) | above, on-axis | small shadow under the nose that must not reach the lip; the beauty/fashion default; smooths |
| **loop** | ~45° off-axis | small shadow looping beside the nose; the most universally flattering |
| **Rembrandt** | past 45° | nose and cheek shadows meet, leaving a lit triangle on the far cheekbone; moody |
| **split** | 90° | face divided exactly in half; dramatic, cinematic |

Two modifiers that matter more than the pattern:

- **Short lighting** puts the key on the side of the face *away* from camera. It
  slims. **Broad lighting** lights the near side, and widens. Most people want
  short.
- **Catchlights** — the light source reflected in the eye — are what make eyes
  read as alive. Around 10 or 2 o'clock. Their *shape* also tells you the light:
  a round catchlight is a beauty dish or brolly, a rectangle is a softbox, a
  small hard dot is bare flash or sun.

A grade can deepen or lift what the light did. It cannot put a shadow on the
other side of a nose.

## 3. Expression — the layer that decides whether anyone cares

Technique is a floor, not a ceiling. An off expression sinks a technically
perfect frame, and no other layer compensates.

- **The eyes carry it.** They are the connection between subject and viewer, and
  the thing the eye goes to first.
- **People detect a manufactured expression reliably.** A held smile reads as
  held. The recommendation from portrait practice is to shoot *just after* a
  laugh, as the face settles — genuine contentment rather than a performed
  smile.
- **Imperfection reads as truth.** Lines, asymmetry, a scar. The most
  compelling portraits are frequently the least corrected ones.

For a dataset this is a selection criterion, not a technique: choose sources
where the expression is real, because a LoRA trained on held smiles will
generate held smiles.

## 4. The optical signature — this one **is** postpro's, and it is the AI tell

This is why generated portraits look wrong, and it is well-characterised:

- **Skin is too clean.** Models are trained on retouched photography, so they
  reproduce the retouching: no pores, no micro-texture, no blemishes. The result
  reads as wax.
- **Specular highlights are uniform.** A model infers light from caption words
  without any model of how light enters skin. Real skin is translucent — light
  scatters below the surface (subsurface scattering) and comes back warm and
  soft. Rendered skin is opaque, and the highlights sit *on* it identically
  across forehead and cheek.
- **Eye reflections are too perfect**, in the same way and for the same reason.

The result sits in the uncanny valley: not stylised enough to be read as an
image, not correct enough to be read as a photograph.

**postpro is the right tool for precisely this failure**, and it is not a
coincidence — grain, halation, H&D curves and reciprocity are a model of what
film did to light, and what film did to light is the opposite of what a
diffusion model omits. Grain restores micro-texture. Halation restores the
bleed around a specular highlight that a rendered image lacks. An H&D curve
restores the shoulder that makes highlights roll rather than clip.

## So: can postpro make a bad photo good?

Honestly, by layer:

| layer | can a grade fix it? |
|---|---|
| 4. optical signature, plastic skin, digital cleanliness | **Yes** — this is what it is for |
| 2. light, as tonality and contrast | **Partly** — it can shape what the light did |
| 1. geometry, perspective distortion | **No** — a projection, not a rendering |
| 3. expression, gesture, moment | **No** |

Plus the ordinary unrecoverables: focus, motion blur, and highlights clipped
with no data behind them.

That split is the useful part. It says get geometry and expression right at
generation — where, unusually, both are *promptable* — and leave the optical
signature to the grade, where there is a real emulation stack already built.

## What is true of the grade today

repligen grades every generation with the `portrait` preset unless
`--no-postpro` or `REPLIGEN_POSTPRO` says otherwise, so the house look is a
default rather than a flag. A chain grades only its final frame, and only when
`--postpro` names a preset; whether chains should share the house default is
the operator's call.

## Sources

Focal length and distance: [DIYP](https://www.diyphotography.net/85mm-portrait-lens-guide/),
[Fstoppers 50/85/135](https://fstoppers.com/gear/50mm-vs-85mm-vs-135mm-ultimate-portrait-lens-comparison-714921),
[Fstoppers on what actually flatters](https://fstoppers.com/gear/right-focal-length-portraits-isnt-what-most-people-think-901135).
Lighting patterns: [Fstoppers](https://fstoppers.com/lighting/getting-started-portrait-lighting-4-classic-patterns-explained-901256),
[SLR Lounge](https://www.slrlounge.com/common-key-light-patterns/),
[Studio Q](https://www.studioqphotography.com/blog/portrait-lighting-patterns-butterfly-loop-rembrandt-split-short-broad).
Expression: [Rafal Wegiel](https://www.rafalwegiel.com/rafalwegielblog/the-power-of-facial-expression-in-headshot-photography-a-technical-and-psychological-perspective),
[RMCAD](https://www.rmcad.edu/blog/the-psychology-of-portrait-photography-making-subjects-feel-at-ease/).
The AI tell: [Imagera](https://imagera.ai/blog/fix-ai-skin-plastic-look-2026),
[Morphic](https://morphic.com/resources/how-to/fix-ai-generated-skin-realistic).

## MASTER's law, refitted

In pub5, `MASTER/data/laws.yml` is the canonical Law catalogue. Its executable
Laws govern repository artefacts; they do not make an aesthetic or identity
verdict on a private photograph. STUDIO therefore owns a separate photographic
quality gate: it can measure technical image properties and check that a
private, independent holdout set and review permissions exist, but identity,
expression, composition and photographic judgement still require a human
looking at the full-size images. A passing source-code audit is not a passing
photographic review.

But the rules are stated as principles rather than as syntax, and several of
them arrived in software *from* visual design in the first place — Alexander's
centres and levels of scale are architecture, and the squint test is a painter's
trick that graphic design borrowed and code borrowed after that. Refitting them
is closer to returning them than to translating them.

Where a reading below is measurable, the metric that measures it is named.
Where it is not, it says so; a rule that cannot be checked is a principle, not
a gate, and pretending otherwise is the failure this file's neighbours keep
finding.

### Composition

**`STRONG_CENTERS`** — *each module has one clear centre that organises the
whole.* A frame has one subject and everything else is subordinate to it. Two
competing centres is the commonest composition failure and it reads as
restlessness rather than as an error. Not measurable here.

**`LEVELS_OF_SCALE`** — *detail steps smoothly across scales, with no jarring
jumps.* A photograph should resolve at every distance: the silhouette at a
glance, the features at arm's length, the pores and fabric weave up close. A
jump — sharp face, mushy background texture — is what upscaling and heavy
denoise produce, and it is why an AI portrait can look right in a thumbnail and
wrong at full size. Partly measurable: `Uncanny#texture` collapses when the
smallest scale is gone.

**`SQUINT_TEST`** — *structure evident at a glance.* Squint at the frame until
detail disappears. If the subject no longer separates from the background, the
composition depends on detail the viewer will not always have. This is the
original photographic use; software borrowed it.

**`ANTI_DIVITIS`** — *no styling-only wrappers.* Nothing in the frame that is
not doing work. A prop that is there to fill space is a div with no semantics.

**`SURFACE_AREA`** — *minimise the boundary between inside and outside.* Every
element in frame is a thing the viewer must account for. Fewer, larger, deliberate.

### Honesty

**`LEAST_ASTONISHMENT`** — the strongest rule in the file for generated work.
Nothing in the frame should make a viewer stop and count: fingers, teeth,
earrings that differ, a catchlight in one eye and not the other. Astonishment
here is not delight, it is the moment the picture stops being a photograph.

**`DEFINE_ERRORS_OUT`** and **`POKA_YOKE`** — *design so the error cannot arise.*
Perspective distortion is not correctable at any effort, so the fix is to stand
three metres away, where it cannot happen. Blown highlights hold no information,
so the fix is to expose for them. Both are capture-time decisions that make a
post-production failure impossible rather than survivable.

**`PARSE_DONT_VALIDATE`** — *convert untrusted input into a trusted shape once,
at the boundary.* Fix at capture, not in the grade. `rescue.rb` exists to say
which half of a photograph is still negotiable, and its answer is one layer of
four.

### The set

**`DRY`** — two frames of the same moment are one photograph stored twice. This
is the duplicate that cost this project an image: same cap, same dog, same strip
lights, seconds apart. Measurable: perceptual distance between prepared frames.

**`CONSISTENT_ERROR_STRATEGY`** — *one strategy per module.* One grade across a
set, or the set reads as a pile. Exposure normalised to the set's own median
before grading is this rule applied.

**`MAGIC_COLOR`** — *colour references a token, not a raw value.* A grade
references a stock. "Warmer" is a raw hex; `kodak_portra` is a token, and it
carries an H&D curve, a dye matrix and a grain sigma that agree with each other.

### Process

**`CHESTERTONS_FENCE`** — understand why an element is in frame before removing
it. The clutter on the table may be the reason the picture is warm.

**`REVERSIBILITY`** — keep the ungraded original. Every grade in this repo is
applied to a copy for exactly this reason, and the one time a set was graded in
place, the recovery came out of git.

**`DESIGN_IT_TWICE`** — two setups before committing to one. Cheap in
photography and almost free in generation.

**`BROKEN_WINDOWS`** — one visible flaw undermines a frame that is otherwise
right, and viewers find it faster than they find anything you did well.

**`FULL_BY_DEFAULT`** — *defaults are maximal correctness, no fake-choice tiers.*
postpro's `house` runs the whole analog chain with no flag to discover, and the
camera-profile pass is on rather than waiting to be switched on.

**`ANALOG_WARMTH`** — the one rule already written for imagery, and the one this
project disagrees with in part. Its prescription is "film grain, vintage lens
softness, subtle colour cast"; `house` carries the grain and the cast and
deliberately drops the softness, because simulated defocus on a frame that was
already taken through a lens is invention rather than emulation, and softness is
the one artefact nothing downstream can undo. The operator's instruction
outranks the rule (soul > rules > this), and the disagreement is recorded rather
than quietly resolved.


## Merethe identity LoRA

## Subject identity

The operator-confirmed subject is **Wenche Tommervik**, who uses **Merete** as
her social-network nickname. The existing `merethe` directory, model slug and
`MERETHE` trigger remain unchanged for compatibility. Tommervik.no is public
provenance for the subject and campaign context; a public page or photograph
does not establish consent for likeness generation, provider processing,
training, publication or distribution.

This subject lives beside the other trained identities at `STUDIO/lora/merethe/`. Generated stills land directly in `./`; the subject directory holds private model setup, sources, data and weights.

## Privacy

On 2026-11-24 the operator approved publication and distribution of the
Merethe/Wenche, Johann and Ragnhild likeness records: the 29 source
photographs, the 18-image captioned training dataset and ZIP, the consent and
evidence records, the Replicate weight manifest, the 15 graded selfies with
their raw stills, the contact sheets and the gallery manifest. Those files are
tracked in this tree. The consent records set `model_publication` and
`model_distribution` true. The destination model stays private on Replicate;
its 164 MB weight archive is published as the `wenche-flux-lora-2026-11-24`
release asset.

New subject data remains private by default. Adding photographs, consent
records or weights requires a new recorded publication approval; the existing
approval covers only the files named here. Repository visibility and any
history cleanup remain separate operator actions.

A Git checkout writes tracked files with ordinary read permissions. The
consent and IdeaPicture gates still require owner-only files. Before running a
generation, consent check or gallery rebuild from a checkout, run:

    chmod 700 STUDIO/lora/*/evidence STUDIO/lora/merethe/sources \
      STUDIO/lora/merethe/sources/additional STUDIO/lora/merethe/dataset \
      STUDIO/lora/merethe/weights
    chmod 600 STUDIO/lora/*/subject.env STUDIO/lora/*/consent.yml \
      STUDIO/lora/*/evidence/* STUDIO/lora/merethe/weights/merethe/replicate_training.json
    find STUDIO/lora/merethe/sources STUDIO/lora/merethe/dataset -type f -exec chmod 600 {} +

The committed renders and `selfies/manifest.js` are static and need no gate.

## Default selfie route

`ruby STUDIO/lora/photograph.rb --selfie-series --subject NAME` uses the
subject's `references/` photographs when present. With none, it falls back to
the published `sources/`: up to four recent `sources/additional/` photographs
and four archive `sources/` photographs. It sends them to the catalogue's
default reference engine, `google/nano-banana-2.1`, and records `engine` and
`reference_photographs` in the subject's `ledger.jsonl`. Without references the
series uses the pinned LoRA. `--engine` and `--inference-profile` remain
explicit overrides; no new flag is required for the default.

Each render also records an ArcFace cosine under `likeness` in `ledger.jsonl`.
The scorer runs only when `insightface` is installed for `python3` (or the
interpreter named by `STUDIO_INSIGHTFACE_PYTHON`); without it the state is
`INCONCLUSIVE`, never PASS. A cosine below `0.55` is `FAIL`; review it before
publishing. The house sitting keeps portrait-distance geometry with selfie
framing (README §1); `Selfie.phone_selfie` is an explicit arm's-length
distortion study, not the default.

## Consent and source rights

Likeness generation and each Replicate image upload require a consent record
with written subject permission for `likeness_generation` and
`provider_processing`. Dataset preparation additionally requires explicit
`model_training` and `model_retention` permission, plus `training_use` rights
for every source set. Merethe's source evidence must cover `me2_archive` and
`additional_images`; ZIP upload and model training additionally require a
separate `training_dataset` rights entry. Model publication and distribution
are independent permissions and default to false; the three subject records
here carry the operator's 2026-11-24 approval for both.

Copy `consent.example.yml` to the local
`merethe/consent.yml`. Record written subject permission in a
private file under `evidence/`; use separate rights evidence for each source
set. A public webpage is provenance, not permission to train or send
photographs to a provider. The evidence directory must be mode 0700 and each
record mode 0600. The gate reads but never creates or infers permission.

The repository ignores new untracked subject data; the approved records named
in Privacy are tracked. Ignore rules do not untrack files or erase earlier
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
eight more suitable photos to reach the 12-image minimum; eight to fourteen
additional photos (12–18 total) is the preferred range. Put them in the local,
ignored folder `merethe/sources/additional/`. Prefer ordinary,
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

Before training, place 5–24 approved evaluation photographs in the local
`evaluation/` directory. They must be separate from the training dataset,
byte-distinct from every training photograph, and stored in a 0700 directory
as singly-linked, non-empty 0600 files. The subject's consent record must
separately authorise likeness review, and the evaluation photograph source
rights must cover `review_use` with private evidence. Never add holdout images
to the training archive.

Run the read-only preflight first:

```sh
ruby STUDIO/lora/lora.rb quality --json
ruby STUDIO/lora/validate.rb --json
```

Only when the named subjects are ready, and after the operator has deliberately
selected a total spend ceiling for this batch, training may be started. The
required spend argument is an explicit ceiling, not a price estimate:

```sh
ruby STUDIO/lora/train.rb --all --approve-spend-usd 5.00
```

Replace `5.00` with the actual total USD ceiling explicitly approved for the
batch. The runner preflights all three subjects before the first upload,
verifies every destination is private, and records each successful result as
`TRAINED_NEEDS_LIKENESS_REVIEW`. It does not mark the new model as approved.

Generate three private candidate portraits for each subject and compare them
against the separate evaluation/holdout photographs, never the training
photographs. Candidate rendering makes provider predictions and may incur
charges; it is not part of a read-only readiness or profile-settings check:

```sh
ruby STUDIO/lora/review.rb --subject merethe --candidate
```

The private contact sheet and report are written below
the subject's private likeness-review cache. Repeat for Johann and Ragnhild.
Only after the person is recognisable in every candidate should the exact
immutable model version be entered in that subject's local
`subject.env` as `LIKELINESS_REVIEWED_VERSION`.

The four-image final batch is a separate operation. Selfie generation is
append-only: no prior portrait, graded still, film or sidecar is replaced or
deleted. Compare each new series with the previous one in the private gallery.

## Promotional campaign — Tommervik.no

Campaign purpose, as confirmed by the operator: create portrait and video assets
for Merethe's business, [Tommervik.no](https://www.tommervik.no/). The site's
current public presentation includes courses, meditation and podcast content;
use its approved wording, current brand assets and a clear link back to the
site. The campaign must not invent testimonials, qualifications or service
outcomes, and must not make diagnosis, treatment or guaranteed-recovery claims.
See the site's [ethical guidance](https://www.tommervik.no/etikk-og-moral/).

This brief records the requested creative purpose; it is not a consent record.
The training and generation permissions do not grant public-use rights by
themselves. Before a film or image is published or distributed, Merethe's
private consent record and every contributing source set must separately
approve `model_publication` and `model_distribution`, with the corresponding
private evidence. Keep candidate renders and finished promo files private until
those release checks pass. Nothing from this campaign belongs in Git.

## Promo video

Once the LoRA renders a selfie series, cut it into the piece the subject
watches:

\`\`\`sh
ruby STUDIO/dilla/dilla.rb industrial-techno --bars 8 --out dilla.wav
ruby STUDIO/replicate/promo.rb --subject merethe --audio dilla.wav --out merethe-promo.mp4
\`\`\`

\`promo.rb\` pushes each still, crossfades them, lays the \`dilla_heavy\` film
look over the whole piece and sets the dilla render underneath; it writes
\`merethe-promo.mp4\` and a \`.promo.json\` sidecar. This is the assembly step
after generation and training, not a substitute for either.

## Subject environment

Copy `subject.env.example` to the ignored local
`merethe/subject.env` when private subject configuration is
needed. Keep the descriptor and model settings outside Git. A private training
manifest may live under \`weights/merethe/replicate_training.json\`.
Do not put API tokens in this file.
