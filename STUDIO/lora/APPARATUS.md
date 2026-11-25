# Apparatus: what the survey changed

`apparatus.rb` renders three operations no camera performs. This note records
what a survey of public implementations and grading practice found, and what
each finding implies for the rig. Sources are at the end, because a claim about
film behaviour is worth nothing without one.

## 1. Slit-scan: the technique is standard, my implementation is coarse

Four working implementations agree on the shape of the operation: keep a
rolling history of frames and, for each output column, read from a different
moment.

[KinoSlitscan](https://github.com/keijiro/KinoSlitscan) (Unity) holds four
history textures and samples them at per-column offsets with bilinear filtering,
so time varies smoothly across the width.
[TimeSlice-Nodes](https://github.com/systms-ai/TimeSlice-Nodes) (ComfyUI) adds
angled, animated and dual-source slices — two clips sliced against each other,
which is a piece nobody is making.
[video-2-slit-scan](https://github.com/andrewringler/video-2-slit-scan),
[slit_scanner_darkly](https://github.com/Pantsworth/slit_scanner_darkly) and
[SlitScan](https://github.com/jawngee/SlitScan) all produce a single still, not
a moving piece.

Apparatus copies column strips of 6 px at a quarter of the delivery size, so
time steps 18 px across the frame. That is why the first render reads as
banding. Two fixes, both local: assemble at half size, and replace the linear
shear with a curve, so the ribbon accelerates through the frame instead of
crawling at the edges. The curve is the artistic decision the linear version
left on the table.

## 2. Film emulation is a density pipeline, not a filter

[filmlab-resolve](https://github.com/peterskotte123/filmlab-resolve) documents
the node order that working colorists use, and it is not the order we run:

1. grade (exposure, balance)
2. **halation** — before the negative, because it is scene light scattering
3. negative LUT — scene to negative density (Kodak Vision3 stocks)
4. push/pull, interlayer, bleach bypass, printer points (one point = 0.025 logE)
5. print LUT — 2383 or 2393, to Rec.709 / PQ / HLG
6. grain

[spektrafilm](https://github.com/andreavolpato/spektrafilm) is the reference
implementation, built from manufacturer datasheets, with spectral calculations
rather than three-channel approximations.
[spectral_film_lut](https://github.com/JanLohse/spectral_film_lut) generates
`.cube` files from the same data.
[OpenDRT](https://github.com/chrisbrejon/OpenDRT-OCIO-Config) is the
alternative for computer-generated images: a picture-formation transform rather
than a stock emulation, and the current state of the art for CG.

**Correction, 2026-11-25.** An earlier draft of this note said the repo ran
halation after the print. That is wrong for Postpro. `STUDIO/postpro/lib/effects_finish.rb`
places `halation` before `film_curve` in the `house` chain, and
`effects_print.rb` applies measured density curves through `HD.channel_curve`
for 2383 and 2393. The critique applies to the model-side chain instead:
`levelsio/analog-film` is a black box, and the `house_v1` curves in
`selfie_series.rb` are hand-tuned. Postpro's effect order is already right.

The fix costs nothing. A `.cube` LUT applies in ffmpeg through `lut3d` and in
the still path through the same filter, at 16-bit, deterministically, offline.
Halation becomes a separate pre-LUT pass: threshold the highlights, blur the red
channel wide, screen it back. That is three `vips` operations and no model.

## 2b. The still look now travels to the cut

`postpro.rb --export-lut house` bakes the whole `house` chain into a 17³
`.cube`: 4913 lattice points, 130 KB, written to `STUDIO/lora/house.cube`. The
video path reads it through ffmpeg `lut3d`, so a cut carries the same print
look as the stills it was filmed from. `STUDIO/postpro/video.yml` gains the
`dilla_print` look, which names the LUT under a new `lut:` key; `promo.rb`
resolves that path against the repository root, because a relative path in a
filter string breaks whenever the cut is run from another directory.

This build of ffmpeg spells the option `file=`, not `filename=`. Newer builds
rename it. The code and its test use `file=`.

## 3. Depth for video must be temporally consistent

[Video-Depth-Anything](https://github.com/DepthAnything/Video-Depth-Anything)
(ByteDance, CVPR 2025 highlight) exists because per-frame depth flickers: each
frame is estimated in ignorance of its neighbours, so a static wall crawls.
`STUDIO/postpro/depth.rb` runs Depth Anything V2 small ONNX frame by frame, so
anything we feed a video model will inherit that crawl.

Two routes. Cheap: smooth the depth sequence locally with an exponential moving
average before encoding — five lines, no new dependency, removes most of the
crawl. Expensive: adopt Video-Depth-Anything, which needs PyTorch and the
weights.

## 4. Grain is a signal, not noise

[AOMedia afgs1](https://github.com/AOMediaCodec/afgs1-spec) and
[DeepFilmGrain](https://github.com/InterDigitalInc/DeepFilmGrain) define film
grain as signal-dependent and spatially correlated: more grain in the midtones,
less in highlights and deep shadow, and grain that moves in clumps rather than
independently per pixel.

Our look uses `noise=alls=6`, which is white, uniform and uncorrelated — the
tell that says "digital filter" to anyone who has printed. The cheap correction
is to modulate noise amplitude by luma in the filter graph, or to scan a real
grain plate once and composite it. The expensive one is FGS synthesis.

## 5. Colour science is a library, not a habit

[colour-science](https://github.com/colour-science/colour) carries the matrices,
transfer functions and chromatic adaptation that our hand-written curves
approximate. Use it when a transform has a name.

## 6. Round two: what else the survey turned up

Six more techniques, read against what this repo can actually run.

- **Datamosh.** [moshpit](https://github.com/CrushedPixel/moshpit) and
  [python-moshion](https://github.com/rjmoggach/python-moshion) drop I-frames so
  motion vectors keep painting over a stale image. Cheap and violent, and the
  look is well worn. Not adopted: the effect is a decoding accident, hard to
  repeat, and it fights the print pipeline.
- **Dual-source slit.** [TimeSlice-Nodes](https://github.com/systms-ai/TimeSlice-Nodes)
  slices two clips against each other. Adopted as `dual_slit`: columns left of a
  sweeping edge read from take one, columns right read from take four, and both
  are sheared through time.
- **Depth parallax.** [depth-parallax](https://github.com/Lakshaaysharma/depth-parallax)
  turns one photo into a 2.5D camera move with a monocular depth map. Adopted as
  `depth_warp`: the local estimator supplies the plane, `vips` `mapim` remaps
  each frame, and the camera pushes in with parallax that a flat zoom cannot
  fake. This is a camera that never existed, made from a still that was never
  photographed.
- **Chronophotography.** [chronophotography](https://github.com/EmaBO97/chronophotography)
  composites motion trails. Adopted as `chronophoto`: twelve poses stacked only
  where the subject moved, so the body repeats and the room holds still.
- **Seamless loops.** [PerfectLoop](https://github.com/SherLock707/PerfectLoop)
  morphs a clip into its own start. Not adopted yet: the cut ends on the bed,
  not on the loop.
- **Scanimation.** [scanix](https://github.com/NancyTana/scanix) builds
  barrier-grid animations, where a striped overlay reveals motion as it slides.
  Not adopted: it is a print artifact, and it needs the viewer's hand.

## What this changes, by cost

| change | cost | why |
|---|---|---|
| `.cube` print LUT through `lut3d`, halation before it | free | measured data beats guessed curves, and the order is the technique |
| half-size assembly and a curved shear | free | the first render bands because time steps 18 px |
| temporal smoothing of depth frames | free | per-frame depth crawls |
| grain amplitude by luma, or a scanned plate | free | white noise reads as a filter |
| depth-fed clip through `minimax/h3-highspeed` | $0.20 | the model invents motion from relief instead of optics |
| Video-Depth-Anything or spektrafilm | gated | PyTorch, or a slow spectral reference implementation |

## Sources

Slit-scan: [KinoSlitscan](https://github.com/keijiro/KinoSlitscan),
[TimeSlice-Nodes](https://github.com/systms-ai/TimeSlice-Nodes),
[video-2-slit-scan](https://github.com/andrewringler/video-2-slit-scan),
[ofxSlitScan](https://github.com/obviousjim/ofxSlitScan),
[temporalis](https://github.com/positlabs/temporalis).

Film and print emulation: [filmlab-resolve](https://github.com/peterskotte123/filmlab-resolve),
[spektrafilm](https://github.com/andreavolpato/spektrafilm),
[spectral_film_lut](https://github.com/JanLohse/spectral_film_lut),
[OpenDRT config](https://github.com/chrisbrejon/OpenDRT-OCIO-Config),
[OpenDRT source](https://github.com/jedypod/open-display-transform).

Round two: [moshpit](https://github.com/CrushedPixel/moshpit),
[python-moshion](https://github.com/rjmoggach/python-moshion),
[depth-parallax](https://github.com/Lakshaaysharma/depth-parallax),
[chronophotography](https://github.com/EmaBO97/chronophotography),
[PerfectLoop](https://github.com/SherLock707/PerfectLoop),
[scanix](https://github.com/NancyTana/scanix),
[video-2-slit-scan](https://github.com/andrewringler/video-2-slit-scan).

Depth: [Video-Depth-Anything](https://github.com/DepthAnything/Video-Depth-Anything),
[Depth Anything V2](https://github.com/DepthAnything/Depth-Anything-V2).

Grain: [afgs1 spec](https://github.com/AOMediaCodec/afgs1-spec),
[DeepFilmGrain](https://github.com/InterDigitalInc/DeepFilmGrain),
[VersatileFilmGrain](https://github.com/InterDigitalInc/VersatileFilmGrain).

Colour: [colour-science](https://github.com/colour-science/colour).

Software cited by those projects but not yet read here: vkdt's Vulkan film
simulation, ART's LUT bridge, spektrafilm-rs. Their claims rest on the
reference implementation above, and none of them has been tested in this repo.

## 7. The 2026-11-25 run, measured

Three sitting-3 stills went first (`--selfie-series --count 3`). The three
promos then filmed four takes each and cut them through `dilla_print`: 37.000 s,
1080x1920, audio intact. The rig produced six pieces per subject — fifteen clips
and three plates — at no model cost.

Two measurements keep the pieces honest.

- **Depth warp moves.** Mean absolute difference between frame 0 and frame 235
  reads 28.3 (johann), 27.5 (merethe), 18.5 (ragnhild) on a 0-255 scale. Before
  the fix below it read 0.55, which is a still pretending to be a camera.
- **Plates hold many poses.** `chronophoto` reads YAVG 92 against 54 for a single
  source frame, and YHIGH 193 against 113. The extra light is the stacked bodies.

Three gotchas worth keeping.

1. `Postpro::Depth.near` returns 0..1 **floats**, not 0..255 samples. Dividing by
   255 flattens the plane to 0.002 and the parallax disappears.
2. This `ruby-vips` build rejects enum keywords on `mapim` and `resize`
   (`interpolate:`, `kernel:`) with `:pointer argument is not a valid pointer`.
   Defaults are the same interpolations, so omit the keywords.
3. `:b-w` must be written `:"b-w"`. Unquoted, Ruby parses it as `:b - w`.
