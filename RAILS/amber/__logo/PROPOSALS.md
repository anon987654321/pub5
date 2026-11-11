# PROPOSALS — plur1bus plates: ten directions for the amber® mark

Open `all-plates.html` in a browser: all ten plates render on one page with the
canonical reference on top and the avatar cuts underneath. Regenerate with
`node generate.mjs` (deterministic, seeded; the glyph outlines and the nine
hairlines are extracted live from `RAILS/amber/app/views/shared/_logo.html.erb`,
so the wordmark and the swoosh geometry cannot drift from the shipped mark).

The brief: ten radically different plates — bit-reduction, motion graphics,
color grading, sparkle pizzazz — with the operator's constraint that the
**original font (outlined Caprasimo glyphs) and the swoosh style and lines
(nine-hairline family + carrier curve) stay on every plate**, and every
embellishment is built around them. Second pass added the sprite-sheet
reference workflow: strict palette discipline, palette cycling, frame
language, avatar-size cuts with the ground removed.

## The crop law

The production partial clips its animated ink to the six glyphs, then paints
the nine white swoosh hairlines over the full logo canvas. The reference SVG
keeps that production order and full-width swoosh. Each study plate preserves
the exact same glyph paths and the nine original white hairline paths,
widths and opacity; it applies one additional glyph clip to the swoosh so its
visible area stays inside the letters. No path is re-drawn or restyled.

- Ink is first, clipped to the original glyph interiors.
- The original nine white hairlines follow, unchanged; only their visible
  region is clipped in the study plates.
- Pixel treatments, stars, frame treatments and misregistration live inside
  the same glyph clip.
- The ground belongs to the study presentation, not the production mark.
  The production partial and live assets are not modified.

## What every plate keeps

- The six source Caprasimo glyph placements for `amber®`, extracted from
  the live partial. No replacement font or live text.
- The nine original white hairline elements, identical in path data,
  stroke width and opacity to the source partial.
- The original stacking order: ink below, swoosh above. Study plates add
  only the glyph clip that limits where the swoosh is visible.

## The ten plates

| # | Plate | Direction | Inside the letters | Law/token mapping |
|---|---|---|---|---|
| 01 | `unum_stipple` | Identity-native stipple | White ink perforated by seeded holes, dissolving left-to-right into solid; sparse signal-green carriers inside the glyphs; canonical white swoosh | `tokens.visual_identity.material` = `greyscale_particle_stipple`; lineage "e pluribus unum"; signal `#C8F55F` far under `max_highlight_area_fraction` 0.08 |
| 02 | `bit8_pixel` | 8-bit bit-reduction | Radial ink quantized to a 7-unit grid in five ramp pastels (16-colour discipline); CRT scanlines fall on the ink; canonical white swoosh | 2026 pixel-logo trend (RESEARCH §4); operator sprite constraints (limited palette, no AA); `motion.default: still` honored |
| 03 | `dither4_press` | 4-bit Bayer dither on paper | One-bit halftone: dark ink on paper, Bayer 4×4 steering a density ramp from sparse dots at the `a` to solid at the `r`; canonical white swoosh | Bit-reduction brief; `composition.surfaces` "flat and structured"; no gradients — dither only |
| 04 | `signal_orbit` | Motion graphics | The radial ink's focus roams (18 s loop); wordmark, hairlines and ground frozen | `motion.default: still` honored at the mark level; the *ink* is the only mover |
| 05 | `hue_flow` | Motion graphics — **palette cycling** | The shipped 4-stop ramp cycles through the wordmark (10 s, offset begins) | 16-bit palette-cycling technique (RESEARCH §6) applied to the brand's own ramp; no new colours |
| 06 | `zoetrope_frames` | Sprite-sheet frames, frozen | The ink holds three exposure frames split inside the letters — ghost, ghost, live — separated by slivers of ground, like a filmstrip; canonical white swoosh | Aseprite frame-strip workflow depicted (RESEARCH §6); animation depicted, not played |
| 07 | `starlight` | Night-sky star field | Night-sky ink (moonlight vertical ramp) and tiny stars, kept only where they fall inside glyphs; canonical white swoosh | Sparkle ask; original hairline geometry and stroke remain unchanged |
| 08 | `prism_rainbow` | Sparkle pizzazz | The candy rainbow poured into the letters — prism ink, canonical white swoosh | Rainbow ask, cropped to the law: the prism ramp lives in the ink and nowhere else |
| 09 | `grade_teal_amber` | Explicit cinematic grade | Amber ink (warm vertical ramp) on a deep teal ground; canonical white swoosh | Color-grading brief; the grade is the ground/ink pair, documented in the plate title |
| 10 | `duotone_riso` | Riso misregistration | Two ink passes a hair out of register — orange beneath, navy above — both clipped to the glyphs (navy double-clipped, inner clip shifted −3,−2), so the orange rims only the right/bottom edges *inside* the letter silhouettes; canonical white swoosh; signal-green registration dots | Print-grit trend; the mark stays in fixed values; misregistration without bleeding |

## Avatar cuts (sprite-workflow deliverable)

`plates/avatars/` — three alpha-transparent SVGs with **no ground plate**,
cropped tight to the letterforms (visible content = glyph interiors only):

| File | Ink | Sizes shown |
|---|---|---|
| `amber-canon.svg` | canonical radial ramp, white swoosh on top | 128 / 64 / 32 px on a checker |
| `amber-bit8.svg` | bit8 quantized cells, original white swoosh on top | 128 / 64 / 32 px |
| `amber-candy.svg` | candy prism linear ramp, white swoosh on top | 128 / 64 / 32 px |

Same locked font and hairline family; drop-in ready for favicon and avatar
slots. The checker in `all-plates.html` proves the alpha channel.

## Constraints honored (audited against the live sources)

- **Original font**: Caprasimo outlines extracted from the partial at run
  time; every layer clips through the same six glyph placements. No
  `<text>`, no `font-family`, no webfont anywhere in the plates.
- **Original swoosh geometry and style**: all nine source path strings,
  white strokes, widths and opacity are preserved exactly. The study clip
  changes visibility only; no path is sampled, stepped, dotted or recoloured.
- **Crop law**: candidate ink and swoosh visibility stay inside the glyph
  interiors. The production reference is the deliberate exception: it keeps
  the shipped full-width hairlines so it can be compared honestly.
- **No copied brand expression**: all artwork is generated original; the
  operator's Grok session and online research informed technique only.
- **No glow/lens-flare/ornamental gradient**: no blur or filter primitives
  in any plate; gradients are the mark's own ink or trail fills.
- **One focal point per plate** (`composition.hierarchy`): the wordmark on
  all ten — with no ground furniture left, the mark is the plate.
- **Reproducible**: every random layer seeded (`rng(57xx)`); a rerun of
  `node generate.mjs` is stable.

## Engineering notes — regressions caught by rendering

1. **clipPath content model.** The first `.mjs` build wrapped the clipPath
   children in `<g>`: `<clipPath><g><use …/></g></clipPath>`. Chromium
   discards invalid clipPath children per the SVG 1.1 content model — the
   clip resolved **empty** and the wordmark vanished from every plate. The
   fix is bare shape children: `<clipPath><use …/><use …/></clipPath>` —
   the same structure the shipped partial already uses.
2. **Stacking order.** A later build drew the hairlines *below* the ink
   rect. Because both layers clip to the same glyphs, the opaque ink hid the
   swoosh inside the letters while the lines kept bleeding across the
   ground outside them — exactly inverted from the shipped mark. The fix is
   the canonical `mark()` helper: ink pass first, hairline pass second,
   both clipped to `#plN-text`; every plate, the reference and the avatars
   go through it.

Review `all-plates.html` to compare the production reference with all ten
candidate plates and the three transparent avatar cuts. The Amber logo
contract tests compare every exported hairline path, width and opacity with
the source partial.

## Files

```
RAILS/amber/__logo/
  generate.mjs         generator — extracts glyphs/hairlines from the live partial
  all-plates.html      all ten plates + reference + avatar cuts on one page
  RESEARCH.md          online research with sources
  PROPOSALS.md         this file
  plates/*.svg         10 plates + reference-original.svg
  plates/avatars/*.svg 3 alpha-transparent avatar cuts
```

Home rationale: the logo is owned by Amber, so its generator, previews and research live beside the app. No candidate replaces the production logo until it is selected. The plates are brand documentation, not production assets; rendered PNGs stay out of the repo and the SVGs remain the source of truth.
