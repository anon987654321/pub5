# postpro

Historical source and behavioral decisions from `pub`, `pub2`, `pub3` and the Git history of `pub4` are indexed in [Postpro archaeological recovery record](#postpro-archaeological-recovery-record). It distinguishes restored effects from intentionally retired mechanisms.

Startup diagnostics, dependency probing and the explicit opt-in dependency-installation path live in `bootstrap.rb`; optional per-effect texture/contrast diagnostics live in `explain.rb`. Loading the entrypoint is observational; `rake postpro:bootstrap` is the intentional installation command.

**Film is a physical process, and postpro models the process rather than imitating the
result.** A filter is a lookup table with an opinion. This is an emulsion: crystals with a
size and a statistics, a base that reflects light back into the layer it came through, a
curve that spends contrast instead of adding it, and a print stock after that. It is the house grade for stills and bounded, constant-rate MP4 clips. Its entry point is
`STUDIO/postpro/postpro.rb`; the video path uses the same grade in-process under explicit frame,
pixel, temporary-storage and runtime budgets. Variable-frame-rate and display-rotated inputs are
refused rather than silently retimed; odd dimensions are rejected rather than cropped or resized.
See [the video archaeology record](#postpro-archaeological-recovery-record).

Give it `--input`, `--output` and `--preset` and it grades one image headless. Give it bare
paths and each is a subject: an image goes through ten random takes, a directory gives a
few random picks from it, and a path that is neither is named and refuses the whole batch
before anything renders. Every render lands in the folder of its source photograph, inside
the checkout or out of it; the root `.gitignore` keeps `postpro_*` renders out of git
wherever they land. Give it nothing and it asks what to grade.
The command `postpro.rb --help` lists every flag. `--capabilities` reports the analogue
direction catalogue and its readiness state; a catalogue entry is not a promise that the
corresponding effect is implemented or enabled on this machine.

The code spans several files. The file `postpro.rb` is the entry point: it boots, runs the
early modes and loads `lib/`, whose files hold the grade, the presets, the film tables and the
command line, one subject per file in the load order `POSTPRO_LIB` names. Video is split across
`motion.rb` (the grade contract and CLI) and `motion_process.rb` (bounded frame IO and child
processes), so neither file becomes another entrypoint monolith. `--vocab-check` reads
`postpro.rb`, `legacy_effects.rb`, `dilla_analog.rb`, `uncanny.rb`, `motion.rb`, `motion_process.rb` and every `lib/` file as one source.
`legacy_effects.rb` holds creative effects recovered from the older `pub/postpro` line, and
`Legacy Postpro restore section` records which of them already had current equivalents. The file `dilla_analog.rb` translates mechanisms
from dilla's analog chains into still images, so that temporal wow and flutter become spatial
registration error. The file `uncanny.rb` measures whether a picture looks rendered,
`rescue.rb` diagnoses a bad photograph, `frame_set.rb` reads a folder as a set, and `depth.rb`
supplies a real depth map when its model is installed.

The file `constitution.rb` is the boundary where MASTER's laws become image-generation
invariants. The original 2019 DCP archive held 1,250 profiles, but the recovery audit found empty `ToneCurve`, `LookTable` and `HueSatDeltas` tables; these are camera sensor-calibration matrices, not film-emulation data. See the [source recovery](https://github.com/anon987654321/pub4/commit/d3b5107911818b7c51e06e540b68a73d56f36784). `camera_profiles.json` preserves 121 VSCO-DCP-derived matrices across Canon,
Fujifilm, Leica, Nikon, Olympus and Sony. EXIF lookup is exact by normalized model or
make+model; an unknown body receives no borrowed manufacturer matrix. The source records
do not declare matrix direction or input/output colour spaces, so the matrices are not
applied to rendered sRGB images. A profile becomes eligible only with the explicit
`matrix_contract: linear_srgb_to_linear_srgb` contract and regression evidence; eligible
matrices are applied in linear light. `baseline_exposure` remains catalogued but is not
applied because its source convention is not established.
`analog_capabilities.rb` backs `--capabilities` with a distinct 200-direction emulation
inventory. Entries remain `unverified` with a null `enabled` value until a concrete code path
and regression test establish readiness; `catalog_complete` means the inventory is present,
while `complete` means all reported directions are verified and enabled. A log named
`postpro.log` is output, and git should not carry it.

## Restored historical creative vocabulary

The `pub` v12.9/v13.3.14 and `pub2` v14.2 vocabularies are preserved as
compatibility names and provenance, not parallel runtimes. Five historic names
already had current equivalents; the other 24 are restored through
`legacy_effects.rb` and the current dispatcher. The complete name-to-effect
mapping belongs in [Legacy Postpro restore section](#legacy-postpro-restore); the repository
lineage and disposition of historic behavior belong in
[Postpro archaeological recovery record](#postpro-archaeological-recovery-record).

The original interactive workflow remains as an operating concept: professional
and experimental intensity, random variations, short effect chains, recursive
batch selection, custom JSON recipes, retries, progress and aggregate statistics.
Those responsibilities now live in named presets, bounded `--random`,
`--rough` and `--heavy` chains, checked recipes, batch processing,
per-variation failure reporting and provenance sidecars. The old prompt flow
and retry/bootstrap code are not restored: loading Postpro stays observational,
dependency installation stays explicit, and every recipe resolves through the
one measured grade dispatcher.

## The checks that catch what does not raise

Run `--vocab-check` after touching a preset, an effect dispatch arm, a stock table, or a recipe
adapter. The check uses Prism's Ruby AST rather than stopping at the first textual `end`:
nested blocks cannot truncate method bodies, and comments or strings cannot masquerade as
executable effects or calls. It checks that every preset step has a real `case fx` arm; stocks,
print stocks and lenses exist and remain reachable; every stock has the required per-stock
table rows; every film curve is monotonic; recipe adapters match callable effects; and effects
are reachable from a preset or a recipe.

Preset fields have a closed vocabulary. Built-in fields and `iso` are explicit; every other
declared field must have an effect-reader contract. For each declared reader, the checker
proves that the corresponding `case fx` arm passes that value into the matching effect call.
Merely mentioning `p[:temp]` in a comment, string, disconnected expression, or neighboring
effect arm does not satisfy the contract. It also follows executable call paths from every
rendering entry point to `apply_finishing_grain`, then runs a tiny in-memory 8×8 probe through
representative colour, monochrome and print presets to catch failures that table inspection
cannot see. A problem produces a non-zero result.

`QualityAnalyzer.report_image` measures decoded-sRGB linear-light luminance. Its
`delta_e_2000` implements the CIEDE2000 formula against published reference pairs, and
`compare_images(reference, actual)` reports mean, median, 95th-percentile and maximum ΔE
for same-dimension, aligned images. It refuses mismatched dimensions rather than silently
cropping or resizing a false comparison. This is the comparison primitive for future
calibrated golden photographs; synthetic colour patches alone do not establish photographic
quality or skin/highlight preservation.

These guards exist because table-driven failures rarely raise by themselves: an effect with no
implementation once returned the input unchanged while the log reported the step as done, and a
temperature that `--describe-preset` printed but no step applied was a lie and not a look. A
historical run found twenty key-reader gaps across the recovered presets; those preset chains
were subsequently repaired. That historical count is not current verification. The live
`--vocab-check` and installed compatible Ruby/libvips regression suites still need to pass before the current
vocabulary or rendered behavior can be called clean.

The table/list flags `--list-presets`, `--list-stocks`, `--list-lenses` and
`--describe-preset` do not need an input photo. `--fit-grain` measures an image, while
`--export-lut` builds a LUT and `--css-filter` emits a CSS approximation.

## The model

A preset is an ordered chain of effects plus the film it is shot on. Per-stock data lives in
several tables keyed by the same symbol: `STOCKS`, which carries granularity, box speed, colour
matrix and the per-channel characteristic curve, then `GRAIN_CHAN_SCALE`, `FILM_BASE`,
`PUSH_RESPONSE`, `RECIPROCITY_SHIFT` and `C41_STOCKS`. A stock missing from one table does not
fail; it quietly becomes a different stock, which is why the vocabulary check refuses a gap.
The matrix of each stock is normalised so that it does dye crosstalk and the curve offsets do
the colour cast, and not both doing the cast.

The fourteen stocks are Kodak Portra, Vision3 in three speeds, CineStill 800T, Ektachrome,
Velvia, Tri-X, Kodachrome, Ilford HP5 and Delta 3200, Kodak Ektar, Fuji Pro 400H and the
Polaroid SX-70. For skin, Portra and Pro 400H are the low-contrast pair, and a high-contrast
slide stock on a face is a choice you have to mean. The black-and-white stocks carry equal
gamma across all three channels, so a colour cast applied before them is thrown away; put the
colour temperature step after the curve or leave it out of a monochrome chain.

## Grain, halation and the tone scale

Grain is a Boolean model. Silver halide crystals are disks dropped by a Poisson process whose
density follows the local grey level, and the developed picture is that binary field filtered
by the observer. The crystal field is generated, clumped, made slightly anisotropic along the
film transport, blurred, and then normalised by its own measured deviation, so whatever the
filter removes the measurement puts back.

Chroma grain is correlated with luma grain because
one crystal layer shadows the next. The grain figure of a stock is its peak luma deviation in
eight-bit levels at mid-grey, a quantity an instrument can check, and `--fit-grain` is that
instrument: point it at a flat scan and it reports the deviation per tone and the crystal size
that implies. Treat its figures as a floor, since its residual is a high-pass and the coarsest
octave goes out with the picture. Rated film keeps its own box speed, each stop of push costs
more, cell size scales with image width, and the finishing grain pass stands down for any
chain that already grains itself.

Every graded picture then passes through a tone anchor before its last grain. Stacked lifts leave
the darkest pixel at fifteen percent grey and the frame reads as milk, so the anchor stretches
the picture's own 0.5th and 99.5th luma percentiles to a printed black and white with one gain on
all three bands, which holds hue, and bends the midtones with a gentle S-curve.
`POSTPRO_ANCHOR=0` returns the unanchored grade.

Halation is a ring. Light that passes through the emulsion reflects off the rear of the base
and re-exposes an annulus around a highlight, not a halo centred on it. The radii differ per
channel because red penetrates furthest, which is why CineStill blooms red.

The `tonemap` effect offers five curves: the ACES fit, Hable, Hejl-Burgess-Dawson, AgX and the
ACES 2 tone scale. AgX rotates into narrower primaries before the sigmoid so that a clipping
channel does not drag hue with it. A preset chooses with `tonemap:` and receives the ACES 2
scale if it says nothing.

## Light and depth

A grade cannot move a shadow to the other side of a nose. The `relight` effect splits the
picture into illumination and reflectance, with a heavy blur of luminance standing for the
light, then puts the light back differently and leaves the surface alone. The correction rides
as a bounded ratio on all three channels, so texture, grain and hue survive. The `aerial_depth`
effect applies the oldest depth cue in painting: distance costs contrast and saturation and
cools the colour. Without a depth map it estimates nearness from local sharpness, a proxy that
will read a sharp cloud as near.

When the `onnxruntime` and `numo-narray` gems and the model weights are present, `depth.rb`
runs Depth Anything V2 small locally and both effects use its map instead. The weights are
fetched out of band into the local ignored depth-model cache, never committed, and each frame's
plane is cached there. That directory does not exist on a fresh checkout. Without the gems or
the weights everything falls back to the proxies, with one quiet log line.

The weights are the fp16 export of `onnx-community/depth-anything-v2-small-ONNX` (Apache-2.0),
a 180 KB graph and 50 MB of external data; the fetch command is under Commands below.

A first estimate takes about twelve seconds a frame on a laptop CPU; later takes of the same
frame read the cached plane. onnxruntime aborts in its native teardown at exit on macOS, so a
command-line run that loaded the model leaves by `exit!` with its own status. `POSTPRO_DEPTH=0`
keeps the proxies, and the test suites set it.

## Bounded video grading

A short, constant-rate clip can use the house grade without launching a new Ruby process for
every frame:

\`ruby STUDIO/postpro/postpro.rb --video input.mp4 --output graded.mp4 --preset portrait\`

The output contract is MP4. The reader probes the streams, preserves rational frame rates, and
refuses ambiguous/variable-rate inputs because silently normalising their timestamps would
change the edit. Per-frame presentation timestamps are read from ffprobe JSON rather than CSV:
Every frame must have a finite presentation timestamp; missing values and numeric overflow such as `1e999` are inconclusive input, not usable timing evidence. H.264 side-data can be appended to the first CSV timestamp line and otherwise make a valid frame
look missing. The focused motion tests include that side-data shape. Audio is copied instead of re-encoded. Grain moves deterministically by frame
by default; `--grain-hold` pins it for a scanned-print texture. When a preset includes
`gate_weave`, its frame-to-frame registration uses a seeded, bounded filtered-noise
source shared with Dilla's tape-speed variation; still-image gate weave remains
one deterministic offset. The `legacy_super8` preset also uses a separate bounded
frame-wide exposure walk for Super 8 lamp/transport flicker; still-image flicker is a
no-op rather than a fake spatial overlay. Work is bounded before decoding
(600 frames, 500 million pixel-frames, a 300-second budget and a 1 GB graded-frame spool by
default); `POSTPRO_VIDEO_MAX_FRAMES`, `POSTPRO_VIDEO_MAX_PIXELS`,
`POSTPRO_VIDEO_MAX_SECONDS`, `POSTPRO_VIDEO_MAX_TEMP_BYTES` and
`POSTPRO_VIDEO_SECONDS_PER_FRAME` allow a validated operator adjustment within hard maxima.
The time estimate is a preflight estimate, not a performance claim. Runtime is checked between
frames and during ffmpeg decode/mux; a single native libvips frame operation cannot be forcibly
interrupted. The video and `.mp4.json` sidecar are published with same-directory atomic links
only after successful muxing. The sidecar records source/output SHA-256, preset, seed/grain,
frame dimensions/rate/count, audio-copy status and measured duration/temporary bytes. The focused test suite is
`cd STUDIO && rake test:motion`.

## Random chains and heavy mode

A bare path, or `--random` with a path (`--random photo.jpg` or `--random --count 10
photo.jpg`), renders several variations of that photograph, each through its own chain, with a
JSON sidecar naming every effect, the seed, the take number, the look and the lane. Each random-chain sidecar also carries a stable `take_id`: a SHA-256 identity bound to the source bytes, seed, take position, look/lane, canonical recipe and renderer digest. Identical rerenders of the same inputs keep the identity; changing any bound input changes it. This identifies Postpro takes without claiming a complete cross-STUDIO inventory. `--random`
with no path draws from the downloads folder instead. Several paths on one line get one family
each. A take is named for what it is, in draw order:
`postpro_photo_03_neon_night_artistic_analog_v1.jpg`. A family of two or more also gets
`postpro_photo_contact.jpg`, every take tiled with its number and look beneath it, so the
family is judged side by side; `POSTPRO_CONTACT=0` leaves it out. The media, sidecars and
contact sheet always sit beside the source photograph. A new run keeps every earlier take and
sidecar. If a generated name or its sidecar already exists, Postpro preserves both and chooses
a timestamped sibling; it never retires earlier output to make room for a new family.

A take is graded exactly as a preset is. Every step, drawn or from a preset, goes through one
dispatch, `grade_step`, which mixes each effect down from the look intensity by its own
factor, scales the subtractive steps by what the source arrived with, and runs the chain in
float with one clamp at the end. Random takes used to call each effect at its raw number with
none of that, and measured on nine photographs (2026-10-27) 69% of them lost the source's
colour or shapes, against 10% of the lighter takes.

Light takes are the default: short chains grown from the presets, ten of them. `--heavy` (or
`POSTPRO_HEAVY=1`) starts each take from a named look instead (noir, neon night, Technicolor,
cross process, infrared and a dozen more), runs that look as its preset does, with its own
stops, exposure time, print stock and lens, and adds at most a few supporting steps, ten in
all. No two takes of a heavy run share a look, and no two share a stock while an unused one
remains.

Every take is then judged against its source on what a colourist protects. It must keep the
source's shapes, its black and white points and at least half its tonal spread. Colour may
move within the look's own budget: how far colourfulness may rise, how far neutral greys may
be tinted, and how far skin may turn in hue, held tightest. The default budgets sit at the
90th percentile of measured light takes, and the palette looks (day for night, cross process,
the night stocks) get more. A take that drains colour on purpose is judged on shapes and
tones alone. Every bound is relative to the source, so a low-key photograph is judged against
its own darkness. A refused take is drawn again, up to three times.

Each run draws a fresh seed and prints it, and `POSTPRO_SEED` renders a family again.

A chain is grown and not sampled. A random subset of the whole effect list is the Photoshop
filter menu and looks like one. A step may join only where some preset already places it
beside everything already picked, so the steps belong to one process. One or two steps carry
the look and the rest sit quietly beneath them. A random take is a clean film grade: nothing
that softens (lens and defocus simulations, diffusion, cross-fades, faded prints), nothing that
prints a relief or a halo (band lifts, edge effects, local contrast), no fringes or distortion,
no frames or overlays, and none of the wear shelf of dust, scanner noise and tape dropouts.
`RANDOM_UNCLEAN` lists them, they are dropped from a look's own steps too, and only `--rough`
admits them. Grain is never optional, because a chain with no crystals in it is a colour filter
with opinions, but it runs at no more than 0.45, felt rather than seen. Black-and-white stocks
develop a panchromatic luminance image, so their looks come out monochrome. Within a run each
picture is drawn against the others and takes a stock no other picture used.

Other modes grade in bulk. The `--watch` flag grades every new photo that lands in a folder,
`--auto` grades the default globs, and `--from-replicate` grades what replicate wrote last.
The `--gallery` flag writes an `index.html` contact page of every render in a folder, beside the
renders it lists. The `--stock-sheet` flag tiles one frame through every stock. Bulk grades and
stock sheets sit beside their source like every other render. A LUT export has no source
photograph, so it goes to the shared dated directory, which `POSTPRO_OUTPUT_DIR` can move; pass
`--output` where the command accepts an explicit destination.

## Reading a frame, and a set

A photograph fails in four independent ways: geometry, light, expression and optics. A grade
can fix only the optical layer and part of the light, and `--rescue` names what it fixed and
what it could not, where a quieter tool would claim success. The `--measure` flag reads texture
numbers and a palette, or with `--against` shows how a grade moved them. It also prints two
readings borrowed from MASTER's laws: the finest octave, which tells a frame at its own
resolution from an upscaled one, and the squint, which reports how much tonal separation
survives a heavy blur. Neither diagnoses anything yet, since their thresholds were drawn on
synthetic frames.

The `--set DIR` flag reads a folder as one set. It names every pair of frames that are one
photograph taken twice and states each frame's exposure in stops from the set's median. It
changes nothing, because moving a frame toward the median changes the look, and that step
belongs to the operator.

## What it does not model

It is not a spectral simulation. Published work that is one starts from measured spectral
sensitivities and dye densities and carries the negative through an enlarger and a paper
stock. That is a different program and needs data this repository does not have. What is
modelled here is the emulsion's statistics, its curve, its crosstalk and its base.

## Config and camera bodies

Presets and defaults come from built-in tables unless `POSTPRO_CONFIG` or a `master.json`
beside the script names more. There is no such file now, so every read takes its built-in
fallback and the default preset is `house`. The camera-profile guard reads
`camera_profiles.json` and matches exact EXIF make/model across six manufacturers. The
current VSCO-DCP-derived records lack a declared matrix direction and colour-space contract,
so the guard leaves rendered sRGB inputs unchanged. A future profile may be applied only
when it declares `matrix_contract: linear_srgb_to_linear_srgb`; the matrix then runs in
linear light. This avoids treating a DCP camera-native transform as an output-sRGB look.
Generated images without EXIF also pass through unchanged.

## Who calls it

The Rails apps reach postpro through `Operator::DeployPaths#postpro_script`, by way of
`Shared::NewsletterVisuals` and brgen's `PostproJob`, and `MASTER/web` grades web photos
through `image_presenter.rb`. The replicate tool hands every fresh generation here by default,
and lora grades its renders the same way. Programmatic invocation goes through
`Master::Io::ScriptDispatch` under the tool name `postpro`, and natural-language routing goes
through `Io::MediaIntent` as `/postpro`. Route new path references through those, and do not
hardcode the file location. 

The file `video.yml` remains the video-generation recipe contract. Postpro no longer starts a
separate Ruby process per frame: `postpro.rb --video` streams frames through the live in-process
grade and then muxes them into MP4 under explicit limits. `DILLA_VIDEO_POSTPRO=0` still gives
a Dilla video export without its optional post-capture treatment.

## Trust

Images, EXIF fields, LUTs, camera profiles, preset names and filenames are untrusted data.
Subprocess calls take argument arrays and never a built shell string. Outputs are written to a
temporary file and moved into place once validated, and metadata may not select Ruby constants,
files or executables. The tool fetches no remote images; if it ever does, it needs an explicit
fetcher that restricts hosts, validates redirects and bounds size.

## Commands

Run these from the repository root.

```sh
ruby STUDIO/postpro/postpro.rb photo.jpg
ruby STUDIO/postpro/postpro.rb one.jpg two.jpg ~/Pictures/trip
ruby STUDIO/postpro/postpro.rb --input in.jpg --output out.jpg --preset portrait
ruby STUDIO/postpro/postpro.rb --random --rough
ruby STUDIO/postpro/postpro.rb --vocab-check
ruby STUDIO/postpro/postpro.rb --measure photo.jpg
ruby STUDIO/postpro/postpro.rb --rescue photo.jpg
ruby STUDIO/postpro/postpro.rb --set ~/Pictures/trip
ruby STUDIO/postpro/postpro.rb --list-presets
ruby STUDIO/postpro/postpro.rb --describe-preset noir
ruby STUDIO/postpro/postpro.rb --export-lut cinematic --output cinematic.cube
ruby STUDIO/postpro/postpro.rb --capabilities

# the depth model, once, into the gitignored models/depth/
mkdir -p STUDIO/postpro/models/depth
for f in model_fp16.onnx model_fp16.onnx_data; do
  curl -fL -o STUDIO/postpro/models/depth/$f \
    https://huggingface.co/onnx-community/depth-anything-v2-small-ONNX/resolve/main/onnx/$f
done
```


## Historical source and restored effects

The following research preserves provenance and disposition for earlier Postpro implementations. The current Ruby entrypoints and checks above remain the executable authority.


### Postpro archaeological recovery record

<sub>Consolidated from `STUDIO/postpro/Postpro archaeological recovery record`.</sub>

Scope: source and history in `anon987654321/pub`, `pub2`, `pub3`, and `pub4`, searched under `postpro`, `Postpro`, and nearby Repligen/Replicate integration names. This is a preservation map, not a claim that old code can be pasted into the current engine unchanged.

## Decisions

- Preserve historic creative language and workflows as design provenance.
- Keep the current measured film model, recipe dispatcher, seeded random-chain engine, provenance sidecars, and vocabulary checks as the runtime source of truth.
- Restore the legacy effect vocabulary through the compatibility layer, not through a second effect engine.
- Do not re-add the old video implementation verbatim. Its functional intent is now recovered in `motion.rb` using in-process frame grading, raw-frame streaming, atomic output, deterministic grain and explicit budgets.
- Keep external dependency installation opt-in. Older startup bootstraps attempted to install gems and system packages from ordinary execution; the current entrypoint must remain observational when loaded or checked.

## Archaeological trail

### `pub`: v12.9 / v13.3.14 — analog and cinematic post-processing

Sources:
- [postpro.rb](https://github.com/anon987654321/pub/blob/a3185f4ec6e6a27e35eeee6718ae3afa11bf49da/postpro/postpro.rb)
- [README.md](https://github.com/anon987654321/pub/blob/a3185f4ec6e6a27e35eeee6718ae3afa11bf49da/postpro/README.md)
- [README2.md](https://github.com/anon987654321/pub/blob/a3185f4ec6e6a27e35eeee6718ae3afa11bf49da/postpro/README2.md)
- [IMPLEMENTATION_COMPLETE.md](https://github.com/anon987654321/pub/blob/a3185f4ec6e6a27e35eeee6718ae3afa11bf49da/postpro/IMPLEMENTATION_COMPLETE.md)
- [completion commit — 29 effects](https://github.com/anon987654321/pub/commit/512715ac6eddfd3100269019bb361927de371968)

The early interface was an interactive batch tool: select professional or experimental mode, choose random treatments or a JSON recipe, match file patterns (including recursive patterns), choose 1–5 variations and 1–5 effects per variation, and see progress and aggregate statistics. It documented retry-on-failure, rotation/debug logging, RGB/RGBA handling, and finishing/polish steps. Professional mode was deliberately restrained; experimental mode admitted stronger distortion. JSON recipes could set simple intensities or effect-specific parameters such as blend modes and borders.

The v13.3.14 specification enumerated 29 user-facing effects. That vocabulary is preserved in `Legacy Postpro restore section` and `legacy_effects.rb`; equivalent present-day implementations are preferred over copying the old pixel math where a measured stock, H&D curve, grain model, or current effect is more truthful.

Historical wording worth retaining as provenance:

> Every pixel carries the weight of photographic history. Every adjustment honors decades of cinematic excellence.

### `pub2`: v14.2.0 and duplicate roots

Sources:
- [postpro/postpro.rb](https://github.com/anon987654321/pub2/blob/ad05242c97fff1b01450434974aad628d7de8628/postpro/postpro.rb)
- [postpro/postpro_README.md](https://github.com/anon987654321/pub2/blob/ad05242c97fff1b01450434974aad628d7de8628/postpro/postpro_README.md)
- [multimedia/postpro.rb](https://github.com/anon987654321/pub2/blob/ad05242c97fff1b01450434974aad628d7de8628/multimedia/postpro.rb)
- [bootstrap commit](https://github.com/anon987654321/pub2/commit/08ce8802f9374ed62e9d1be61c664d2bf6b53bb8)

The code and README existed under both `postpro/` and `multimedia/`. The v14 line emphasised cinematic presets, one-command integration with Repligen, config-driven options, and dmesg-style startup diagnostics. Both copies are archaeological evidence, not a reason to keep duplicate implementations in the current tree.

### `pub3`: multimedia consolidation

Sources:
- [multimedia/postpro.rb](https://github.com/anon987654321/pub3/blob/835f9199d605b6a6ae1f32cd207919c115a06b47/multimedia/postpro.rb)
- [multimedia/postpro/README.md](https://github.com/anon987654321/pub3/blob/835f9199d605b6a6ae1f32cd207919c115a06b47/multimedia/postpro/README.md)
- [move-to-root commit](https://github.com/anon987654321/pub3/commit/b0f76f553de9a6056b07ed4b987acf49407fc11f)

The documented core had Portra, Vision3, Velvia and Tri-X; camera-profile corrections; portrait skin protection; film curves and highlight roll-off; micro-contrast; Portrait, Landscape, Street and Blockbuster presets; random exploration; and an explicit Repligen handoff. The pipeline wording was: generate, save, process, final output. The user-visible presets and concepts survive in the current preset/stock/effect system, even where the old implementation or numbers have been replaced.

### `pub4`: measured house grade and restoration

The present implementation lives under `STUDIO/postpro/`, with `lib/` holding the effect dispatch, presets, stocks, grain, random chains, recipe handling, pipeline, sidecars, audits and CLI. `motion.rb` owns the video grading contract and CLI, while `motion_process.rb` owns bounded frame IO, timestamp checks and subprocess lifecycles.

The camera archive has a separate lineage and should not be mistaken for film emulation. The 2019 `pub/postpro/cameras_lightroom_vsco.tgz` held 1,250 DCPs covering 121 camera bodies, ten stock labels and six VSCO tone variants. The recovery commit records that `ToneCurve`, `LookTable` and `HueSatDeltas` were empty in all 1,250 files; the same body's stock variants often shared one matrix (Portra 400 and Fuji 400H were byte-identical), with 22 distinct matrices observed among the 33 bodies carrying a given profile. The recovered 3×3 values are camera sensor-calibration data, not film stocks or emulsion looks. The original implementation applied them directly to an already rendered image; pub5 now preserves the evidence but refuses that path until the transform domain and direction are explicit and tested. Source: [pub4 DCP recovery commit](https://github.com/anon987654321/pub4/commit/d3b5107911818b7c51e06e540b68a73d56f36784).

Current recovery anchors:
- [Legacy Postpro restore section](#legacy-postpro-restore)
- [legacy_effects.rb](legacy_effects.rb)
- [recipe.rb](lib/recipe.rb)
- [random_chain.rb](lib/random_chain.rb)
- [grade_step.rb](lib/grade_step.rb)
- [vocab_check.rb](lib/vocab_check.rb)

The new engine preserves the original user intent but intentionally changes the mechanics: effects go through one dispatcher; source headroom and look-specific intensity are respected; calculations remain floating-point until a single final cast; random recipes must survive measured source-preservation checks; every output can carry the seed, chain and provenance; and AST-based vocabulary checks establish that recipe/preset options reach executable effect calls. Historical claims of “true randomization” do not substitute for those current proofs.

## The deleted 2026 photographic proposal notes

The two documents that were folded into implementation—not lost to an accidental delete—are
still recoverable at their exact historical snapshot:
- [Pub4 STUDIO/AMBITION.md — all 168 proposals](https://github.com/anon987654321/pub4/blob/5c15297107d131eef8881241f6e84190670a2225/STUDIO/AMBITION.md)
- [Pub4 STUDIO/lora/PHOTOGRAPHY.md — the four-layer photography model and refitted visual laws](https://github.com/anon987654321/pub4/blob/5c15297107d131eef8881241f6e84190670a2225/STUDIO/lora/PHOTOGRAPHY.md)
- [The later folding/deletion commit](https://github.com/anon987654321/pub4/commit/80709c0712559031fef10fe486f530ac35b185fc), whose message says those ideas now stand beside the code that uses them.

This record preserves the trail without reintroducing two competing top-level specifications.
The four independent failure layers remain the most important rule: **geometry** is decided
before grading; **light** can be reshaped tonally but its direction cannot be moved; **expression**
is a capture/generation decision; and **optical signature** (skin texture, specular response,
grain, halation and highlight shoulder) is the grade's proper scope.

| Historical visual law or proposal | Current owner / status |
| --- | --- |
| Strong centres, levels of scale, squint test, least astonishment | Prompt/selection principles; current generation prompts and current generation prompts. They are not all objectively measurable gates. |
| Define errors out / poka-yoke | `rescue.rb` states geometry, focus, motion blur, expression and clipped source highlights honestly instead of claiming a grade can repair them. |
| Parse, don't validate; refuse unsupported settings | Replicate's model-specific input vocabularies, `Chain.problems`, and Postpro's checked recipe/preset vocabularies. |
| DRY for near-identical frames | `frame_set.rb` fingerprints and near-duplicate detection. |
| One strategy per set | `frame_set.rb` normalises exposure to the set before applying a coherent grade. |
| Magic color / optical emulsion tokens | Postpro's stock tokens bind curve, dye response, speed and calibrated grain instead of independent arbitrary sliders. |
| Reversibility / chesterton's fence | Original source is retained; output guards refuse source overwrite; grades write separate outputs and provenance. |
| Full by default / analog warmth | The house grade defaults to its complete physical chain; the camera DCP inventory is preserved but not applied until matrix direction and colour-space contract are explicit; blur that would invent new defocus remains intentionally excluded. |
| Uncanny score before and after grade | Preset sidecars already record before/after readings. Chain sidecars now do too, together with input/output hashes and quality warnings. |
| All rendered pathways share the camera-profile guard | A vocabulary audit requires every output path to reach `camera_corrected`. The current DCP-derived entries fail closed because they do not declare a tested input/output matrix contract; no active camera correction is claimed. |
| Golden references with perceptual ΔE and explicit skin/highlight bounds | sRGB transfer and linear-light luminance regressions now guard the measurement basis; QualityAnalyzer implements reference-tested CIEDE2000 and an aligned-image comparison API. Calibrated natural-image fixtures and explicit skin/highlight bounds remain open; synthetic pixels are not a substitute. |
| A measured specular-uniformity score and monotonically improving uncanny score | Still open: whole-frame highlight spread is only a proxy, not a facial-region/specular-scattering measurement; no monotonic quality target is calibrated. |
| Video shutter angle, coherent bloom/halation, gate-hair, telecine and still/video parity | The bounded CFR video pipeline carries seeded gate weave and the restored global Super 8 exposure-flicker walk. Shutter-angle treatment and reference parity fixtures remain future work; no trailing-frame blend is misrepresented as a physical shutter. |

The 168 numbered ideas were a menu, not a mandate to ship every model name, price, or experimental stage
as a runtime default. The maps above make the old intent findable while distinguishing measured
behavior from proposals.

## Later `pub4` change trail

These commits explain important implementation decisions that a code-only snapshot can
obscure:

- [Split `postpro.rb` into `lib/` under the 300-line cap](https://github.com/anon987654321/pub4/commit/66f2c9527f99165ae6bb35801b4e5d65275c796e): preserve small, readable effect and pipeline modules rather than grow another monolith.
- [Make the vocabulary audit read entrypoint and libraries together](https://github.com/anon987654321/pub4/commit/6d3d06f57daf1d6b379d181dbcfaeffa071f31bd): a declared effect must resolve to the implementation the grade actually calls. This branch adds `motion.rb` to the source inventory too.
- [Give Postpro CLI suites a render budget](https://github.com/anon987654321/pub4/commit/909e55b24765611d4b2be0211a727c3ee4f5549f): tests that can render must have bounded cost and not silently turn into hours-long work.
- [Grade random takes like presets and protect photos](https://github.com/anon987654321/pub4/commit/650827110ed9bee560bdf980bbe03b778c016d18): use the calibrated shared grade dispatcher and measured source-preservation checks rather than raw effect strengths.
- [Balance takes before the look and hold exposure through it](https://github.com/anon987654321/pub4/commit/dd721801be0505c838a2131fa042d2254e85ea46): keep source exposure as an explicit invariant, except where exposure itself is the selected look.
- [Treat reciprocity failure as lost exposure, not a veil](https://github.com/anon987654321/pub4/commit/0c5e2d16d9f51a4f9162dfee193e7b234c3416ef): model analog effects according to the physical process, not a convenient overlay.
- [Keep blur, relief and artefacts out of random takes; preserve monochrome stocks](https://github.com/anon987654321/pub4/commit/da763765392fed477fe303ba19987a6297a77c31): random variation must remain coherent and B&W stocks must render monochrome.
- [Restore real depth maps without native exit aborts](https://github.com/anon987654321/pub4/commit/93b8a65b9eb9f4768762563b4f27333ad4a0f44c): optional model-based depth should degrade intentionally, and native teardown must not report a completed output as failure.
- [Remove the original per-frame video path after measurement](https://github.com/anon987654321/pub4/commit/ec2cdf458f6f571692fea1ea97e8335881b56135): the reason for this branch's bounded in-process replacement, not an obsolete detail to lose.

## Lost or changed behaviour: disposition

| Historical capability or idea | Present disposition |
| --- | --- |
| 29 named creative effects | All 29 names have current equivalents or compatibility implementations; see `Legacy Postpro restore section`. |
| Professional vs experimental intensity lanes | Evolved into coherent named random lanes and opt-in `--rough` / `--heavy`; not copied as a second independent effects mode. |
| JSON recipes with effect-specific options | Preserved through `recipe.rb`, `RECIPE_ALLOWED` and the shared grade dispatcher; vocabulary audit tests reachability. |
| Recursive input patterns and multi-variation batches | Present-day batch/prompted entry points are the supported interface; output names, sidecars and family contact sheets are more explicit. |
| Retry/error recovery, logs and statistics | Current per-variation failures and structured startup/output diagnostics avoid hiding a partial batch failure. Do not revive automatic dependency installation as part of retries. |
| Camera profiles and stock-specific grain | Evolved to camera-profile data, measured stock tables, calibrated grain and `--fit-grain`; use those as the authority. |
| Repligen handoff and post-generation film look | Current Replicate calls grade by default (portrait by default); `--no-postpro` is the intentional escape hatch. See `../replicate/replicate.rb` and `../replicate/models.yml`. |
| Video/frame-sequence grading | Recovered as `motion.rb` / `motion_process.rb` and `--video`: one Ruby process, ffmpeg raw-frame streaming, in-process Postpro, atomic final MP4, deterministic moving/held grain, and frame/pixel/time/temp-byte budgets. Constant-rate MP4 only; variable-rate inputs and mismatched frame counts are refused. The old per-frame subprocess path remains retired. |
| The old `apply_effects` / `apply_effects_from_recipe` internals | Not restored: the shared recipe and grade dispatchers replace them. Keeping both would create two sources of truth. |

## The video experiment, its removal, and the recovered in-process path

The implementation commit [9ac4b113](https://github.com/anon987654321/pub4/commit/9ac4b11332762333da58f8ec4358eec7cbbcb1d4) introduced `Postpro::Motion`, CLI `--video`, and eight tests. It captured the right product rules:

- inspect actual streams with ffprobe; do not trust extensions;
- preserve the original dimensions, the true rational frame rate (for example, 24000/1001), and audio without re-encoding;
- run the same Postpro grade so stills and moving frames do not diverge into two looks;
- distinguish deterministic moving grain (base seed plus frame index) from deliberately held grain;
- print frame count and a runtime estimate before expensive work; test the estimate, audio preservation, reproducibility, and the fact that the grain modes actually produce different output.

The removal commit [ec2cdf45](https://github.com/anon987654321/pub4/commit/ec2cdf458f6f571692fea1ea97e8335881b56135) explains why that implementation is not to be restored verbatim: it launched a fresh Ruby process per frame; measured render time was about an hour per minute of 1080p rather than the promised six minutes, and two tests timed out. Its own estimate was therefore not trustworthy.

The replacement on this branch implements the central correction: ffmpeg streams packed RGB frames through one process, each frame is graded by the live Postpro methods in memory, and only compressed graded frames are spooled under a cumulative byte cap. It estimates work before decoding, enforces maximum frames/pixels and a runtime budget checked around every frame operation and subprocess (native libvips processing within a single frame is not forcibly interruptible), refuses frame-rate ambiguity and metadata/decoded-frame count mismatches, copies audio without re-encoding, assembles to a temporary MP4 and publishes the video plus checksum sidecar with same-directory atomic links only after successful grading. Tests cover fractional rates, seed modes, dimensions, audio, repeatability, held-vs-moving output and preservation of a pre-existing output on failure. The GitHub-only edit environment did not execute those tests; `cd STUDIO && rake test:motion` and the full `cd STUDIO && rake check test` remain required evidence before describing this path as verified on a real host.

## AMBITION (the 168 proposals): provenance and as-built state

The proposal menu "168 ways to get there" was written against pub4 (2026-08-25, preserved at
[pub4@5c1529710](https://github.com/anon987654321/pub4/blob/5c15297107d131eef8881241f6e84190670a2225/STUDIO/AMBITION.md),
read-only) and is not carried into this repository as a document: the register keeps backlog
administration out of Markdown, and most of the menu is either built or obsolete here. The
group-level disposition, so the recovered document stays legible from this tree:

| § | Group | Disposition in pub5 |
| --- | --- | --- |
| A | Chain engine (1–24) | The repligen chain engine did not migrate; the generation lane is `../lora/` with `../replicate/`. Items 7 and 11 — per-shot provenance sidecars and the contact-sheet fan-out — are built (`lib/sidecars.rb`, `lib/contact_sheet.rb`, `lib/random_takes.rb`, `--heavy --random`). |
| B | Chain vocabulary (25–46) | Not migrated as chains. Individual capabilities exist where a single tool needs them (`depth.rb`, `lib/relight.rb`). |
| C | Geometry inversion (47–58) | Built as runtime data: `../lora/guides.yml` `layers.geometry` (`portrait_distance_m`, `selfie_distance_cm`, the ask-for-distance rule). |
| D | Light (59–71) | `layers.light` carries the four patterns, short/broad and the catchlight rule; `lib/relight.rb` covers the one generative stage. |
| E | Expression (72–81) | `layers.expression` carries the selection rule; dataset curation follows it in `../lora/`. |
| F | Defeating the uncanny (82–98) | Built: `uncanny.rb` measures texture, tonal range, clipping and specular spread; `../lora/judge.rb` calibrates thresholds against private references and ratchets them (items 96–98). |
| G | House look (99–116) | Portrait grade is the default with `--no-postpro` as the escape hatch; house preset in `lib/presets.rb`; sidecars publish the grade parameters (114). Contact-sheet mode is `lib/contact_sheet.rb` (110). LUT export (115) and golden-image perceptual fixtures (111–112) remain open in the existing `media_effects` convergence row (`MASTER/convergence.yml`). |
| H | Video (117–128) | Built as the in-process `motion.rb` / `motion_process.rb` path documented below. |
| I | Rescue (129–140) | `rescue.rb`; the honest verdict rules travel with it. |
| J | LoRA (141–155) | Consent gates, hash manifests and held-out evaluation are executable (`../lora/validate.rb`, `../lora/judge.rb`); checkpoint scoring uses the judge metrics (151). |
| K | Knowing (156–168) | Partial: the selfies manifest and contact sheets are the gallery (156); the judge is the measurable proxy. Revisit tracking, cost-per-keeper and the monthly catalogue re-survey are not built. |

## Verification boundary

This document is a historical map, not a test receipt. Current effect reachability, pixel behaviour and CLI behaviour are established by the live `--vocab-check`, focused Postpro tests and `cd STUDIO && rake check test`. A historical commit message saying “green” is evidence about that past revision only.


### Legacy Postpro restore

<sub>Consolidated from `STUDIO/postpro/Legacy Postpro restore section`.</sub>

For the repository-by-repository lineage and the disposition of other historical behaviors, see [Postpro archaeological recovery record](#postpro-archaeological-recovery-record).

The archived `anon987654321/pub/postpro` v13.3.14 line exposed 29 user-facing creative
effects.

Five of those already had current equivalents in STUDIO/postpro:

- `light_leaks`
- `lens_distortion`
- `bleach_bypass`
- `day_for_night`
- `chromatic_aberration`

The remaining 24 archive names have been restored through
`STUDIO/postpro/legacy_effects.rb` and wired into the current dispatcher and recipe
vocabulary:

- `film_grain`
- `film_halation`
- `bloom_effect`
- `cross_process`
- `golden_hour_glow`
- `lomo`
- `sepia`
- `teal_and_orange`
- `anamorphic_simulation`
- `vhs_degrade`
- `color_fade`
- `soft_focus`
- `double_exposure`
- `polaroid_frame`
- `tape_degradation`
- `frame_distortion`
- `super8_flicker`
- `cinemascope_bars`
- `halftone_print`
- `film_scratches`
- `film_stock_emulation`
- `sprocket_holes`
- `lens_flare`
- `glitch`

The compatibility implementations are deliberately improved rather than byte-for-byte
copies of the archive. Film-stock emulation delegates to the current measured H&D curve
and stock matrix. VHS, halation, bloom, cross-process, anamorphic and grading aliases
delegate to current implementations where those are more physically grounded. The
remaining effects preserve the old creative affordance with bounded parameters.

Named `legacy_*` presets restore the useful archival looks without changing the current
`house` grade.

`super8_flicker` is temporal, not a still-image texture: in the bounded video path it
applies a seeded, low-frequency, frame-wide exposure variation in linear light. A still
image has no time axis, so the effect is a no-op there. The former three blurred grey
rectangles were not film flicker and have been removed.

The old internal `apply_effects`, `apply_effects_from_recipe` and random driver
functions are not restored because current postpro already has a safer recipe engine,
measured random-chain generator, provenance, and validation.

This restore does not resurrect the old frame-by-frame video implementation verbatim. The experiment introduced in [9ac4b113](https://github.com/anon987654321/pub4/commit/9ac4b11332762333da58f8ec4358eec7cbbcb1d4) was removed in [ec2cdf45](https://github.com/anon987654321/pub4/commit/ec2cdf458f6f571692fea1ea97e8335881b56135): it launched a fresh Ruby interpreter for every frame (about 0.46 seconds of boot each), measured roughly an hour per minute of 1080p against its six-minute estimate, and had two of eight tests time out. `motion.rb` now recovers the product intent with one process, in-memory frame grading, deterministic moving/held grain, exact rational frame rates for constant-rate sources, audio-copy muxing, atomic final output plus checksum-bearing provenance sidecar, and bounded frames/pixels/runtime/temp bytes (runtime is checked between frames and during subprocess work; a single native frame operation cannot be forcibly interrupted). It refuses variable-rate or frame-count-ambiguous input instead of silently changing timing. Shutter-angle treatment remains a future video-specific effect; the current live grade is reused unchanged rather than inventing a second implementation. The new tests are authored but not executed in this GitHub-only session. See [Postpro archaeological recovery record](#postpro-archaeological-recovery-record) for the contract.

## Dilla analog bridge

Dilla's analog processing was also mined for mechanisms that make sense in a still-image
domain.

`dilla_head_bump` translates the tape chain's low-frequency head bump into broad
luminance density.

`dilla_tape_saturation` translates the liveset's tanh tape drive into a restrained image
soft-clip/shoulder, preserving the current film stock as the colour authority.

`dilla_vinyl_bandlimit` translates vinyl/tape bandwidth loss into a very shallow spatial
high-frequency roll rather than a generic blur.

`dilla_phasy` translates the NastyVCS phase-offset sum (`[0, 13, 29, 47]` audio samples)
into tiny deterministic chromatic/spatial registration offsets. It is an image analogue,
not a literal sample-to-pixel conversion.

`dilla_console_sum` translates several gently voiced parallel console passes into a
small spatially offset sum.

Named looks now expose the useful Dilla chain vocabulary: `dilla_vinyl_hot`,
`dilla_summing_phasy`, `dilla_tape`, and `dilla_acetate`.

Temporal audio phenomena such as real capstan wow/flutter cannot be truthfully
reproduced in one still frame; those belong in the video/frame-sequence path, where the
deformation can evolve over time.
