# RESEARCH — plur1bus plates

Research for the ten-plate amber® mark sweep: what the plur1bus series
refers to, how its canonical title treatment works, and which 2026
logo/motion/grading directions the plates draw on. Sources were read online
in November 2026; repo sources were read live in this checkout.

## 1. What "plur1bus" refers to

- *Pluribus* is the Apple TV series created by Vince Gilligan (premiered
  2025-11-07, set in Albuquerque; a hive-mind premise built on "e pluribus
  unum"). Source: <https://en.wikipedia.org/wiki/Pluribus_(TV_series)>.
- The show stylizes the title as **PLUR1BUS** — the "I" written as "1",
  originally Carol's purple-sharpie hand lettering. Sources:
  <https://www.reddit.com/r/pluribustv/comments/1rwdqc8/plur_1_bus_thoughts_on_the_title_and_its>
  and <https://dirt.fyi/article/2025/11/it-was-all-yellow> ("Pluribus
  (styled PLUR1BUS) in purple sharpie").
- The show's color language is deliberate and rule-bound: the 60:30:10
  palette discipline and yellow as the hive's happiness color.
  Sources: <https://www.reddit.com/r/pluribustv/comments/1pc30o9/why_is_pluribus_shot_in_3_colors_video_by>
  and the dirt.fyi color-theory piece above.

**Repo tie-in.** The pub5 identity already speaks this language:
`MASTER/data/tokens.yml#tokens.visual_identity` names the material
`greyscale_particle_stipple`, the lineage line "e pluribus unum — out of
many, one readable form", and the series name in this sweep borrows the
show's "1" stylization. The amber mark is the "one readable form" that the
many carriers resolve into.

## 2. The canonical title treatment: particle stipple

- The *Pluribus* main titles were created by editor Joey Reinisch using a
  particle simulation (RowByte's Stipple): thousands of carriers that
  assemble and dissolve the lettering. Interview:
  <https://www.rowbyte.com/blog/pluribus-stipple>.
- Trade coverage frames the sequence as "The Many Become One in 'Pluribus'
  Main Titles", with Dave Porter's theme. Source:
  <https://www.gema.org/news/the-many-become-one-in-pluribus-main-titles>.

**Repo tie-in.** This is the same material the repo already mandates
(`tokens.visual_identity.material`, law-family `VISUAL_PARTICLE_STIPPLE_*`):
a face/mark that is a field of carriers, never a solid skin. Plate 01 is the
direct homage; plate 07 shows the same idea as motion frames.

## 3. The canonical amber mark (what every plate must keep)

`RAILS/amber/app/views/shared/_logo.html.erb` (amber-057) is the source of
truth, verified pixel-equivalent against the browser's own text rendering:

- Wordmark: the real Caprasimo glyph outlines for "amber®" in font units
  (2048/em), six placements at 120 viewBox units riding descending rotated
  baselines (−9.882° → −0.641°).
- Swoosh: nine white hairlines in one curve family
  (`M50,180 C200,100 400,200 600,100 S850,160 950,130` translated down),
  stroke widths 0.5 → 4 top to bottom.
- The original textPath carrier curve `M50,220 C250,180 750,180 950,220`
  (dropped as dead code from the partial in 8544e23b, still the canonical
  carrier the letters ride).
- Ink: an animated radial gradient (#ffb999 → #e6cce6 → #cce6cc → #99e6e6)
  clipped by the glyph mask; the brand-mark exception to the theme palette
  ("a brand mark is painted in its own fixed values", `scan:
  intentional-colors` in the partial).
- Contract test: `RAILS/amber/test/logo_contract_test.rb` — viewBox
  0 0 1000 500, hairline widths, outlined glyphs, no `<text>`/webfont.

The generator (`generate.rb`) extracts the glyph outlines and the nine
hairlines from the live partial at run time, so the plates cannot drift from
the shipped mark.

## 4. 2026 directions the plates draw on

| Direction | Source read | Plate |
|---|---|---|
| Ultra-crisp pixelated logos: sharp edges, high-contrast grids, mathematical rhythm | <https://www.zekagraphic.com/10-logo-design-trends-2026> | 02 |
| Retro 8-bit/Y2K pixel logo comeback | <https://www.brandcrowd.com/blog/logo-design-trend-the-retro-pixel-logos> | 02, 03 |
| Pixel art as 2026 motion-graphics style (loops, icons, transitions) | <https://din-studio.com/pixel-art-style-nostalgic-and-modern-digital-design-trend-of-2026> | 02 |
| SVG mask + animated gradient text (CodePen staple) | <https://codepen.io/horsted/details/ZKQbKK>, <https://codepen.io/tag/svg%20text> | 04 (frozen), reference |
| Retro glitch logo treatments | <https://github.com/konstantindenerz/codepen-archive> (animated-logo-glitch-effect-retro-look) | 10 (scanline pass) |
| Synthwave sun/grid snippets (sliced sun, neon horizon) | <https://speckyboy.com/css-javascript-snippets-synthwave> | 06 |
| Print grit: overprint misregistration, layered proof aesthetics | <https://littlerockprinting.com/graphic-design-trends-to-modernize-your-print-materials> | 08 |
| 2026 trend surveys (motion, minimalism, emerging systems) | <https://digitalsynopsis.com/design/graphic-design-trends-2026>, <https://panze.co/blog/logo-design-trends> | sweep framing |

## 5. Sparkle pizzazz (rainbows, ponies, shooting stars)

The operator asked for Starks-style pizzazz. The plates keep it inside the
brand's own geometry: the rainbow is the hairline family re-tinted per line
(04) or an arc behind the mark (09); the shooting star is the hairline
family given comet trails and star heads (05); the pony is a pixel sprite
standing on a hairline (09). No emoji, no copied campaign art, no baked-in
text — the wordmark stays original pub5 artwork on every plate.

## 6. Provenance statement

- Online sources were opened via web search on 2026-11-11; quotes and
  stylization claims above come from those pages.
- Repo claims come from live files in this checkout at 8544e23b.
- The plates themselves are original generated artwork (seeded, reproducible
  via `generate.rb`); no external imagery was embedded.
