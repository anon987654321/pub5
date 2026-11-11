# PROPOSALS — plur1bus plates: ten directions for the amber® mark

Open `all-plates.html` in a browser: all ten plates render on one page with the
canonical reference on top and the avatar cuts underneath. Regenerate with
`node generate.mjs` (deterministic, seeded; the glyph outlines and the nine
hairlines are extracted live from `RAILS/amber/app/views/shared/_logo.html.erb`,
so the wordmark and the swoosh geometry cannot drift from the shipped mark).
`generate.rb` is the original Ruby provenance of the same idea, kept for the
record; the Node port is canonical since the working sandbox lost its Ruby.

The brief: ten radically different plates — bit-reduction, motion graphics,
color grading, sparkle pizzazz — with the operator's constraint that the
**original font (outlined Caprasimo glyphs) and the swoosh style and lines
(nine-hairline family + carrier curve) stay on every plate**, and every
embellishment is built around them. Second pass added the operator's
sprite-sheet reference workflow: strict palette discipline, palette cycling,
frame tags, avatar-size cuts with the ground removed.

## What every plate keeps

- The six Caprasimo glyph placements for "amber®" (amber-057, no `<text>`,
  no webfont) as a clip mask — the ink changes, the letterforms never do.
- The nine white-style hairlines in their exact curve family and 0.5→4
  width progression, restyled per concept (stepped, dotted, one-bit, comet,
  phosphor-warm, olive) so they stay visible on each ground.
- The 1000×500 stage and the original carrier curve family
  `M50,180 C200,100 400,200 600,100 S850,160 950,130` (+ translations).

## The ten plates (rework: the mark fills the frame, the swoosh is cropped to the lockup)

| # | Plate | Direction | Embellishment | Law/token mapping |
|---|---|---|---|---|
| 01 | `unum_stipple` | Identity-native stipple | Seeded perforation carriers dissolve the wordmark left-to-right into solid ink — many carriers, one readable form; hairlines become dotted carrier streams; sparse signal-green carriers | `tokens.visual_identity.material` = `greyscale_particle_stipple`; lineage "e pluribus unum"; signal `#C8F55F` as sparse accent (far under `max_highlight_area_fraction` 0.08) |
| 02 | `bit8_pixel` | 8-bit bit-reduction | Radial ink quantized to a 7-unit pixel grid in five ramp pastels; hairlines stepped onto the same grid (`shape-rendering: crispEdges`); CRT scanlines; **sprite palette rail: five ramp chips + signal chip + three EMPTY palette slots** — the 16-color discipline made visible | 2026 pixel-logo trend (RESEARCH §4); operator sprite constraints (limited palette, no AA); scanlines are static — `motion.default: still` honored |
| 03 | `dither4_press` | 4-bit Bayer dither on paper | Ordered-dither ink in two spot colors; one-bit hairlines; thin carrier rules | Bit-reduction brief; `composition.surfaces` "flat and structured"; no gradients — dither only |
| 04 | `signal_orbit` | Motion graphics | The radial ink's focus roams behind the letters (18 s loop); wordmark, hairlines and ground frozen | `motion.default: still` honored at the mark level; the *ink* is the only mover |
| 05 | `hue_flow` | Motion graphics — **palette cycling** | The shipped 4-stop ramp cycles through the wordmark (10 s, offset begins); a chip rail below shows the four stops, chevrons, and one outlined chip for the wrap-around stop — the cycle made visible | The 16-bit palette-cycling technique (RESEARCH §7) applied to the brand's own ramp; no new colors introduced |
| 06 | `zoetrope_frames` | Sprite-sheet frames, frozen | Two onion-skin ghost frames step up-left of the live frame at half-unit (sub-pixel) offsets; film sprockets; **frame-tag chips: filled chip = live frame, outlined chips = ghosts, chevrons between, tick ruler below** | Aseprite frame-tag/onion-skin workflow depicted (RESEARCH §7); sub-pixel technique per 2dwillneverdie; animation depicted, not played |
| 07 | `starlight_comet` | Shooting stars | Hairlines exit as comet trails (fade left, bright right) with star heads; one large comet above the mark; star field; moonlight ink | Sparkle ask; hairline geometry untouched, only stroked with a trail gradient |
| 08 | `pony_rainbow` | Sparkle pizzazz | Pastel sky bands, rainbow arc rising behind the mark (cropped by the frame), candy gradient ink, pixel pony standing on a hairline past the ®, twinkles | Rainbows + ponies ask; pony is original pixel art standing on the canonical line |
| 09 | `grade_teal_amber` | Explicit cinematic grade | Teal ground, amber ink, warm hairlines, teal→amber grade ramp chip | Color-grading brief; ramp chip documents the grade like a LUT strip |
| 10 | `duotone_riso` | Riso misregistration | Navy main ink + orange-red ghost offset (multiply feel), olive hairlines **masked out of the glyphs** (`id-around` mask) so they weave around the letterforms | Print-grit trend; the mark stays in fixed values; hairlines cropped around letters without touching them |

## Avatar cuts (sprite-workflow deliverable)

`plates/avatars/` — three alpha-transparent SVGs with **no ground plate**,
cropped tight to the lockup plus the hairline crests:

| File | Ink | Sizes shown |
|---|---|---|
| `amber-canon.svg` | canonical radial ramp | 128 / 64 / 32 px on a checker |
| `amber-bit8.svg` | bit8 quantized cells + stepped hairlines | 128 / 64 / 32 px |
| `amber-candy.svg` | candy prism linear ramp | 128 / 64 / 32 px |

Same locked font and hairline family; drop-in ready for favicon and avatar
slots. The checker in `all-plates.html` proves the alpha channel.

## Constraints honored (audited against the live sources)

- **Original font**: Caprasimo outlines extracted from the partial at run
  time; every plate clips its ink through the same six glyph placements.
  No `<text>`, no `font-family`, no webfont anywhere in the plates.
- **Original swoosh style and lines**: the nine-hairline family is
  extracted verbatim (`d` strings and widths) from the partial. Restyles
  never re-draw the geometry — 02 steps the *same sampled curve* onto the
  pixel grid; 10 masks the same lines around the glyphs.
- **No copied brand expression**: all artwork is generated original; the
  operator's Grok session and online research informed technique only.
- **No glow/lens-flare/ornamental gradient**: no blur or filter primitives
  in any plate; gradients are the mark's own ink or trail fills.
- **One focal point per plate** (`composition.hierarchy`): the wordmark on
  all ten; rails/chips are subordinate furniture.
- **Reproducible**: every random layer seeded (`rng(57xx)`); a rerun of
  `node generate.mjs` is stable.

## Engineering note — the clipPath regression caught by rendering

The first `.mjs` build wrapped the clipPath children in `<g>`:
`<clipPath><g><use …/></g></clipPath>`. Chromium discards invalid clipPath
children per the SVG 1.1 content model — the clip resolved **empty** and the
wordmark vanished from every plate (only the hairlines rendered). The fix is
bare shape children: `<clipPath><use …/><use …/></clipPath>` — the same
structure the shipped partial already uses. Every plate is verified in
headless Chromium after the fix (`scripts/plates_png.mjs` renders the page to
PNGs under `download/amber-logos/`).

## Files

```
MASTER/docs/visual/plur1bus-plates/
  generate.mjs         generator (canonical) — extracts glyphs/hairlines from the live partial
  generate.rb          original Ruby provenance (superseded by the Node port)
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
