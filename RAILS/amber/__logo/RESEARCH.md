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
- Swoosh: nine white hairline elements in one curve family
  (`M50,180 C200,100 400,200 600,100 S850,160 950,130` translated down),
  stroke widths 0.5 → 4 top to bottom. In production they sit over the ink
  and run across the full canvas; study plates preserve the exact paths,
  widths and opacity but clip their visible region to the glyph interiors.
- The original textPath carrier curve `M50,220 C250,180 750,180 950,220`
  (dropped as dead code from the partial in 8544e23b, still the canonical
  carrier the letters ride).
- Ink: an animated radial gradient (#ffb999 → #e6cce6 → #cce6cc → #99e6e6)
  clipped by the glyph mask; the brand-mark exception to the theme palette
  ("a brand mark is painted in its own fixed values", `scan:
  intentional-colors` in the partial).
- Contract test: `RAILS/amber/test/logo_contract_test.rb` — viewBox
  0 0 1000 500, hairline widths, outlined glyphs, no `<text>`/webfont.

The generator (`generate.mjs`) extracts the glyph outlines and the nine
hairlines from the live partial at run time, so the plates cannot drift from
the shipped mark.

## 4. 2026 directions the plates draw on

| Direction | Source read | Plate |
|---|---|---|
| Ultra-crisp pixelated logos: sharp edges, high-contrast grids, mathematical rhythm | <https://www.zekagraphic.com/10-logo-design-trends-2026> | 02 |
| Retro 8-bit/Y2K pixel logo comeback | <https://www.brandcrowd.com/blog/logo-design-trend-the-retro-pixel-logos> | 02, 03 |
| Pixel art as 2026 motion-graphics style (loops, icons, transitions) | <https://din-studio.com/pixel-art-style-nostalgic-and-modern-digital-design-trend-of-2026> | 02 |
| SVG mask + animated gradient text (CodePen staple) | <https://codepen.io/horsted/details/ZKQbKK>, <https://codepen.io/tag/svg%20text> | 04, 05, reference |
| 2026 trend surveys (motion, minimalism, emerging systems) | <https://digitalsynopsis.com/design/graphic-design-trends-2026>, <https://panze.co/blog/logo-design-trends> | sweep framing |

## 5. Sparkle pizzazz

The rainbow direction uses the candy prism ramp as the ink (08). The
night-sky direction adds seeded stars that survive only where they fall
inside the glyphs (07). Both preserve the original nine white swoosh paths,
stroke widths and opacity; the study clip changes only their visible region.
No pony, character or external campaign art was imported.

## 6. Sprite-sheet craft (second pass)

The operator's reference session (a Grok chat log supplied 2026-11-11: strict
8-bit constraints — blocky pixels, limited 16-color palette, no
anti-aliasing — then 16-bit technique notes, then avatar-size exports with
transparent backgrounds) mapped onto the plates as follows. Sources opened to
back the techniques:

- **Palette discipline / empty palette slots.** Sprite sheets ship indexed
  palettes; Aseprite's palette control ("Palette Control — copy & paste,
  resize") is the workflow anchor. Source: <https://www.aseprite.org>.
  → Plate 02 quantizes its ink to the five-ramp palette on a strict grid —
  the discipline is the palette itself, not a rail drawn on the ground
  (an earlier rail was removed under the crop law).
- **Color cycling (palette animation).** "Color cycling animates a picture
  without touching a single pixel — you rotate the palette underneath it"
  (Mark Ferrari technique). Sources:
  <https://the-pixel.art/articles/color-cycling>,
  <https://blog.prototypr.io/color-cycling-in-pixel-art-c8f20e61b4c4>.
  → Plate 05 cycles the brand's own 4-stop ramp through the wordmark — the
  cycle is the ink itself (an earlier chip rail was removed under the crop
  law).
- **Frame tags, onion skinning, sprite-sheet export.** Aseprite: "Tag
  Frames — include several animations in the same file tagging sections";
  "Onion Skin — see other frames as reference". Source:
  <https://www.aseprite.org>.
  → Plate 06 lays the ink out as a sprite-sheet strip: three exposure
  frames split inside the letters — ghost, ghost, live — separated by
  slivers of ground, the sheet furniture cropped away.
- **Sub-pixel animation.** "'Sub-pixel animation' means animating your
  anti-aliasing … shifting individual pixels frame-to-frame" — depth and
  motion without extra frames. Source:
  <https://2dwillneverdie.com/tutorial/give-your-sprites-depth-with-sub-pixel-animation>.
  → Plate 06's frame strip reads left-to-right across the letters, the
  stepping depicted statically inside the glyph mask.
- **Avatar-size cuts with transparent ground.** The reference workflow's
  final deliverable was avatar-sized icons on alpha-transparent ground.
  → `plates/avatars/*.svg`: the same locked font and hairlines, no ground
  rect, shown at 128 / 64 / 32 px on a checker in `all-plates.html`.

The log's content (a pixel-cat mascot brief for a personal brand) is the
operator's separate project — only its *techniques* transferred here; no
subject matter, imagery or copy was imported.

## 7. Provenance statement

- Online sources were opened via web search on 2026-11-11; quotes and
  stylization claims above come from those pages. The sprite-technique
  sources (§6) were opened the same day.
- Repo claims come from live files in this checkout.
- The plates themselves are original generated artwork (seeded, reproducible
  via `node generate.mjs`); no external imagery was embedded.
