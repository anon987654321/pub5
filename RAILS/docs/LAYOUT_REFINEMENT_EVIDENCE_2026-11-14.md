# Layout refinement evidence — RAILS, 14 November 2026

Rendered-evidence records for the manual layout sweep over `RAILS/**`, kept in the
contract `VISUAL_LAYOUT_REFINEMENT_EVIDENCE` demands: each record names the Laws the
edits repair, carries a distinct before/after screenshot pair, and declares the viewport
the pair was captured at. Screenshots are real chromium captures, not mockups; the
capture rigs are throwaway and only the pairs are committed.

## Record 1 — mrdamascy `docs/ui-preview.html`: dead icon resource

- laws: IMG_ALT, LAZY_IMAGES
- before: screenshots/refinements/2026-11-14/mrdamascy-ui-preview-before.png
- after: screenshots/refinements/2026-11-14/mrdamascy-ui-preview-after.png
- viewport: 390x844

The three brand rows carried `src="/home/z/my-project/pub4/RAILS/__other/mrdamascy/public/icon-192.png"`
— an absolute path into a foreign checkout that can never resolve in any deployment, so
every viewer saw the browser's broken-image glyph. The repair points the three `<img>`
elements at the app's own served asset `/icon-192.png` (the file ships in
`mrdamascy/public/`). IMG_ALT was already satisfied — the marks are decorative with the
name in the adjacent text, so the `alt=""` they carry is the correct spelling, and the
before pair proves the mark itself was the defect, not the attribute. LAZY_IMAGES was
already satisfied (`loading="lazy"` on all three). The before screenshot shows the
broken-image glyph beside "Mr. Damascy"; the after screenshot shows the app's real
wrap icon rendering from `/icon-192.png`.

## Record 2 — hjerterom `application.scss`: stylesheet imported six stylesheets that do not exist

- laws: FOCUS_VISIBLE, AESTHETIC_FLAT_SEMANTIC
- before: screenshots/refinements/2026-11-14/hjerterom-harness-before.png
- after: screenshots/refinements/2026-11-14/hjerterom-harness-after.png
- viewport: 1280x900

hjerterom's root stylesheet began with `@use "pub4_stack"`, `@use "x_base"`,
`@use "x_root"`, `@use "x_shell"`, `@use "x_widgets"`, `@use "x_responsive"` — six
files that exist nowhere in pub5 (verified with a whole-tree search; every other app
imports the flattened shared gem barrel `_stack.scss` plus `_dialect_tokens.scss`).
The compile could never have succeeded, so the app rendered as an unstyled document
wherever its assets were built from source. The repair re-points the imports at the
stack the Gemfile already ships (`@use "stack"`, `@use "dialect_tokens" as x`,
`meta.load-css` for `shell`, `shell_widgets`, `responsive`), maps the phantom
`--x-*` palette/radius variables onto the tokens the shared mixins actually emit
(`--surface`, `--surface-elevated`, `--border`, `--text-secondary`, `--radius-pill`,
`--radius-card`, `--radius-medium`), includes the family's one focus-ring owner
(`meta.load-css("focus_ring")` + `--focus-ring: 2px solid var(--app-accent)`), and
adds the missing dark default (`@include x.dark-tokens`) so `:root` carries a palette
again while the light toggle keeps `@include x.light-tokens`. FOCUS_VISIBLE is
repaired for real: the keyboard focus indicator that the file never had is now
declared and consumed (`_focus_ring.scss` owns the `:focus-visible` rule), and the
map-home nav links gain an explicit `:focus-visible` outline. The harness page uses
hjerterom's own classes (`map-home-nav`, `map-home-dock`, `btn-primary`,
`hjerterom-heart-marker`); the before screenshot is the empty-cascade state a failed
asset build ships, the after screenshot is the repaired cascade with every token
resolving. All six family stylesheets now compile under dart-sass 1.81.0
(hjerterom 152 kB, mrdamascy 36 kB, mytoonz 123 kB, bsdports 155 kB, amber 277 kB,
brgen 518 kB), so the repair is proven against the real compiler, not a syntax
hunch.

## Repairs outside the screenshot contract (HTML metadata, no rendered layout change)

- HTML_LANG (severity error): `hjerterom/app/views/layouts/mailer.html.erb` shipped a
  bare `<html>`; it now reads `<html lang="no">`, matching the application layout.
  The brgen `<html>` hit in the same sweep is a comment in an ERB comment block, not
  an element — the real tag carries `lang="<%= Current.locale || I18n.locale %>"`.
- The mrdamascy `application.scss` / `_tokens.scss` FOCUS_VISIBLE hits the per-file
  regex raises are false positives and were left alone deliberately: the app's
  interactive surfaces are covered by the global `:focus-visible` rule in
  `_base.scss` consuming the `--focus-ring` token `_tokens.scss` declares. Adding a
  duplicate rule to satisfy the regex would have been the dishonest fix.
