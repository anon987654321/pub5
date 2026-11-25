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

Our chain does the opposite: `levelsio/analog-film` as a black box, then hand
rolled `vips` curves inside `house_v1`. The order is wrong — halation lands
after the print instead of before the negative — and the curves are guesses
where measured data exists.

The fix costs nothing. A `.cube` LUT applies in ffmpeg through `lut3d` and in
the still path through the same filter, at 16-bit, deterministically, offline.
Halation becomes a separate pre-LUT pass: threshold the highlights, blur the red
channel wide, screen it back. That is three `vips` operations and no model.

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

Depth: [Video-Depth-Anything](https://github.com/DepthAnything/Video-Depth-Anything),
[Depth Anything V2](https://github.com/DepthAnything/Depth-Anything-V2).

Grain: [afgs1 spec](https://github.com/AOMediaCodec/afgs1-spec),
[DeepFilmGrain](https://github.com/InterDigitalInc/DeepFilmGrain),
[VersatileFilmGrain](https://github.com/InterDigitalInc/VersatileFilmGrain).

Colour: [colour-science](https://github.com/colour-science/colour).

Software cited by those projects but not yet read here: vkdt's Vulkan film
simulation, ART's LUT bridge, spektrafilm-rs. Their claims rest on the
reference implementation above, and none of them has been tested in this repo.
