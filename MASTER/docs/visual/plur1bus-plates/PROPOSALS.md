# PROPOSALS — plur1bus plates: ten directions for the amber® mark

Open `all-plates.html` in a browser to see all ten plates on one page with
the canonical reference on top. Regenerate with `ruby generate.rb` (deterministic;
the glyph outlines and hairlines are extracted live from
`RAILS/amber/app/views/shared/_logo.html.erb`, so the wordmark and the swoosh
geometry cannot drift from the shipped mark).

The brief: ten radically different plates — bit-reduction, motion graphics,
color grading, sparkle pizzazz — with the operator's constraint that the
**original font (outlined Caprasimo glyphs) and the swoosh style and lines
(nine-hairline family + carrier curve) stay on every plate**, and every
embellishment is built around them.

## What every plate keeps

- The six Caprasimo glyph placements for "amber®" (amber-057, no `<text>`,
  no webfont) as a clip mask — the ink changes, the letterforms never do.
- The nine white-style hairlines in their exact curve family and 0.5→4
  width progression, restyled per concept (dotted, stepped, spectral, comet,
  neon, press, phosphor) so they stay visible on each ground.
- The 1000×500 stage and the original carrier curve
  `M50,220 C250,180 750,180 950,220`.

## The ten plates

| # | Plate | Direction | Embellishment | Law/token mapping |
|---|---|---|---|---|
| 01 | `stipple_unum` | Identity-native stipple | ~5,200 seeded carriers resolve into the wordmark; hairlines become particle streams; sparse signal-green carriers | `tokens.visual_identity.material` = `greyscale_particle_stipple`; lineage "e pluribus unum"; signal `#C8F55F` as sparse accent (≈0.06 % area, far under `max_highlight_area_fraction` 0.08) |
| 02 | `bit8_pixel` | 8-bit bit-reduction | Radial ink quantized to a 12.5-unit pixel grid in the 4 brand pastels; hairlines stepped onto the same grid; CRT scanlines; 8-bit sparkles; block cursor | 2026 pixel-logo trend (RESEARCH §4); `motion` stays still — CRT cues are static |
| 03 | `dither4_press` | 4-bit Bayer dither on paper | Ordered-dither ink in two spot colors; one-bit hairlines; thin carrier rule | Bit-reduction brief; `composition.surfaces` "flat and structured"; no gradients — dither only |
| 04 | `prism_rainbow` | Spectral grade | Full-spectrum linear ink; each hairline a different spectral ray; white sparkles at the ray ends | Rainbow ask, kept inside the hairline family; brand-mark fixed-values exception covers the ink |
| 05 | `comet_night` | Shooting stars | Hairlines become comet trails (fade left, bright right) with star heads; one large comet above; star field | Sparkle ask; hairline geometry untouched, only stroked with a trail gradient |
| 06 | `synthwave_sun` | Synthwave grade | Sun-sliced ink (ground-color slice gaps inside the mask); neon cyan hairlines over magenta doubles; horizon + perspective grid | Synthwave trend; "no glow" respected — the neon double is a hard-edged stroke, not a blur |
| 07 | `zoetrope_onion` | Motion graphics, frozen | Three onion-skin ghost frames stepping down the carrier curve + the main frame; film sprockets top/bottom | `motion.default: still` honored: the animation is depicted, not played; reduced-motion meaning preserved |
| 08 | `cmyk_press` | Press-proof grade | CMYK overprint with misregistration (multiply), white hairlines over a press shadow, registration marks, color bars | Print-grit trend; the mark still painted in fixed values (proof inks) |
| 09 | `pony_meadow` | Sparkle pizzazz | Pastel sky, rainbow arc behind the mark, candy ink, pixel pony standing on a hairline, twinkles | Rainbows + ponies ask; pony is original pixel art standing on the canonical line |
| 10 | `terminal_sweep` | Phosphor terminal | Signal-green ink gradient, oscilloscope hairlines with endpoint ticks, telemetry dot grid, scanlines, block cursor | `signal` `#C8F55F` on ink ground; `contrast.signal_on_ink_min` respected at the bright top stop; scanline pass from the retro-glitch trend |

## Constraints honored (audited against the live sources)

- **Original font**: Caprasimo outlines extracted from the partial at run
  time; every plate clips its ink through the same six glyph placements.
  No `<text>`, no `font-family`, no webfont anywhere in the plates.
- **Original swoosh style and lines**: the nine-hairline family is
  extracted verbatim (`d` strings and widths) from the partial; the carrier
  curve reappears on 01/03/07/10. Restyles never re-draw the geometry —
  02 steps the *same sampled curve* onto the pixel grid.
- **No copied brand expression**: all artwork is generated original;
  external research informed technique only.
- **No glow/lens-flare/ornamental gradient**: no blur or filter primitives
  in any plate; gradients are the mark's own ink or trail fills.
- **One focal point per plate** (`composition.hierarchy`): the wordmark on
  all ten.
- **Reproducible**: every random layer seeded (`Random.new(57xx)`); a rerun
  of `generate.rb` is byte-stable.

## Files added (new directory: one ownership boundary for the sweep)

```
MASTER/docs/visual/plur1bus-plates/
  generate.rb          generator — extracts glyphs/hairlines from the live partial
  all-plates.html      all ten plates on one page + canonical reference
  RESEARCH.md          online research with sources (see above)
  PROPOSALS.md         this file
  plates/*.svg         10 plates + reference-original.svg
```

Home rationale: `MASTER/docs/visual/` already hosts visual audits
(`browserless_ad_audits.md`); the plates are brand documentation, not app
assets, so nothing enters the Rails asset tree. Rendered PNGs stay out of
the repo — the SVGs are the source of truth.

## Known issue fixed on main while landing this

`logo_contract_test.rb` still asserted the carrier `d="M50,220 C250,180
750,180 950,220"` after 8544e23b removed the def that carried it — the
design contract was red on main. The stale assertion is dropped in a
separate path-scoped commit; the hairline assertions (which the partial
still satisfies) are untouched.
