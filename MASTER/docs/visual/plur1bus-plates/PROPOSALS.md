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

## The crop law (operator directive, pass three)

> "Crop away everything that bleeds outside the character/letter edges …
> the way it will appear on amber frontpage" — "only make the area inside
> each letter visible."

The shipped partial already paints this way: the ink layer is clipped to the
glyph mask (`clipPath #text-mask`) and the nine white hairlines ride **on
top** of that ink. The plates extend the same rule to everything:

- ink pass first, clipped to the glyph interiors;
- hairlines second, **also clipped to the glyph interiors** — the swoosh
  exists only where the letters are;
- any embellishment (perforation, cells, scanlines, stars, misregistration)
  lives inside the same clip; nothing renders past the letter edges;
- the ground rect is the one surface allowed to show — it is the plate, not
  the mark. Rails, chips, sprockets, ponies and star fields that once sat on
  the ground were removed in this pass for violating the law.

## What every plate keeps

- The six Caprasimo glyph placements for "amber®" (amber-057, no `<text>`,
  no webfont) as a clip mask — the ink changes, the letterforms never do.
- The nine hairlines in their exact curve family and 0.5→4 width
  progression, restyled per concept (stepped, dotted, one-bit, comet-faded,
  cream, dark) but never re-drawn.
- The shipped stacking order: ink below, hairlines on top, both masked to
  the letters.

## The ten plates

| # | Plate | Direction | Inside the letters | Law/token mapping |
|---|---|---|---|---|
| 01 | `unum_stipple` | Identity-native stipple | White ink perforated by seeded holes, dissolving left-to-right into solid; dotted swoosh punched through in the ground colour; sparse signal-green carriers | `tokens.visual_identity.material` = `greyscale_particle_stipple`; lineage "e pluribus unum"; signal `#C8F55F` far under `max_highlight_area_fraction` 0.08 |
| 02 | `bit8_pixel` | 8-bit bit-reduction | Radial ink quantized to a 7-unit grid in five ramp pastels (16-colour discipline); hairlines stepped onto the same grid (`crispEdges`); CRT scanlines fall on the phosphor, not the ground | 2026 pixel-logo trend (RESEARCH §4); operator sprite constraints (limited palette, no AA); `motion.default: still` honored |
| 03 | `dither4_press` | 4-bit Bayer dither on paper | One-bit halftone: dark ink on paper, Bayer 4×4 steering a density ramp from sparse dots at the `a` to solid at the `r`; swoosh as one-bit rules | Bit-reduction brief; `composition.surfaces` "flat and structured"; no gradients — dither only |
| 04 | `signal_orbit` | Motion graphics | The radial ink's focus roams (18 s loop); wordmark, hairlines and ground frozen | `motion.default: still` honored at the mark level; the *ink* is the only mover |
| 05 | `hue_flow` | Motion graphics — **palette cycling** | The shipped 4-stop ramp cycles through the wordmark (10 s, offset begins) | 16-bit palette-cycling technique (RESEARCH §7) applied to the brand's own ramp; no new colours |
| 06 | `zoetrope_frames` | Sprite-sheet frames, frozen | The ink holds three exposure frames split inside the letters — ghost, ghost, live — separated by slivers of ground, like a filmstrip; dark swoosh on top | Aseprite frame-strip workflow depicted (RESEARCH §7); animation depicted, not played |
| 07 | `starlight_comet` | Shooting stars | Night-sky ink (moonlight vertical ramp); the swoosh carries a comet fade — faint tail at the `a`, bright head at the `r`; tiny stars seeded over the lockup, kept only where they fall inside glyphs | Sparkle ask; hairline geometry untouched, only re-stroked with a trail gradient |
| 08 | `pony_rainbow` | Sparkle pizzazz | The candy rainbow poured into the letters — prism ink, white swoosh | Rainbows + ponies ask, cropped to the law: the rainbow lives in the ink and nowhere else |
| 09 | `grade_teal_amber` | Explicit cinematic grade | Amber ink (warm vertical ramp) on a deep teal ground; cream swoosh | Color-grading brief; the grade is the ground/ink pair, documented in the plate title |
| 10 | `duotone_riso` | Riso misregistration | Two ink passes a hair out of register — orange beneath, navy above — both clipped to the glyphs (navy double-clipped, inner clip shifted −3,−2), so the orange rims only the right/bottom edges *inside* the letter silhouettes; cream swoosh; signal-green registration dots | Print-grit trend; the mark stays in fixed values; misregistration without bleeding |

## Avatar cuts (sprite-workflow deliverable)

`plates/avatars/` — three alpha-transparent SVGs with **no ground plate**,
cropped tight to the letterforms (visible content = glyph interiors only):

| File | Ink | Sizes shown |
|---|---|---|
| `amber-canon.svg` | canonical radial ramp, white swoosh on top | 128 / 64 / 32 px on a checker |
| `amber-bit8.svg` | bit8 quantized cells, stepped hairlines on top | 128 / 64 / 32 px |
| `amber-candy.svg` | candy prism linear ramp, white swoosh on top | 128 / 64 / 32 px |

Same locked font and hairline family; drop-in ready for favicon and avatar
slots. The checker in `all-plates.html` proves the alpha channel.

## Constraints honored (audited against the live sources)

- **Original font**: Caprasimo outlines extracted from the partial at run
  time; every layer clips through the same six glyph placements. No
  `<text>`, no `font-family`, no webfont anywhere in the plates.
- **Original swoosh style and lines**: the nine-hairline family is
  extracted verbatim (`d` strings and widths) from the partial. Restyles
  never re-draw the geometry — 02 steps the *same sampled curve* onto the
  pixel grid; 07 re-strokes the same paths with a trail gradient.
- **Crop law**: nothing renders outside the letter interiors except the
  ground rect; verified plate-by-plate in headless Chromium against the
  shipped partial rendered on the same sheet.
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

Review harness: `scripts/render_plates.mjs` (outside the repo) renders the
shipped partial — ERB stripped, its `.animated-gradient` style inlined —
above the reference and all ten plates into one contact sheet, so each plate
is compared against the original on the same page.

## Files

```
MASTER/docs/visual/plur1bus-plates/
  generate.mjs         generator — extracts glyphs/hairlines from the live partial
  all-plates.html      all ten plates + reference + avatar cuts on one page
  RESEARCH.md          online research with sources
  PROPOSALS.md         this file
  plates/*.svg         10 plates + reference-original.svg
  plates/avatars/*.svg 3 alpha-transparent avatar cuts
```

Home rationale: `MASTER/docs/visual/` already hosts visual audits
(`browserless_ad_audits.md`); the plates are brand documentation, not app
assets, so nothing enters the Rails asset tree. Rendered PNGs stay out of
the repo — the SVGs are the source of truth.
