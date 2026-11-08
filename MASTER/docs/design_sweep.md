# Design sweep — the RAILS stylesheet workflow, codified

The operator's standing request: MASTER's Laws reflected pixel-by-pixel in a full
stylesheet sweep of RAILS/**. Most of that reflection already exists as Laws and
instruments; a second rule file would be a competing policy catalogue, which the
constitution forbids. This page records the mapping from pixel rules to their
owners, the real gaps, the packaging truth, the sweep phases in the repo's real
verbs, and the eight lenses the operator supplied for the work. Provenance: the
operator's 2026-11-08 session on engines, dialects and pixel Laws; scope
classification lives in [expectations.yml](expectations.yml) under
`own_repos_repair`.

## The Laws already own the pixels

| Pixel rule asked for | Owning Law or instrument |
| --- | --- |
| Flat surfaces, no shadow or glow | `NO_DECORATIVE_FX`, `FLAT_PIXELS` (MASTER/law/surface.rb) |
| Spacing on one scale | `EIGHT_PX_RHYTHM` (MASTER/law/surface.rb), against tokens.yml `scale.space_px` |
| No `!important` wars | `NO_IMPORTANT` (MASTER/law/web.rb) |
| No inline `style=` | `NO_INLINE_STYLES` (MASTER/law/html.rb) |
| No wrapper pyramids | `ANTI_DIVITIS` (MASTER/law/web.rb) |
| Type on a ramp | `CLAMP_TYPOGRAPHY` (MASTER/law/css.rb), `TYPEFACE_PER_ROLE`, `LINE_HEIGHT_ON_SCALE` (MASTER/law/geometry.rb) |
| One colour source | MASTER/data/tokens.yml, the one authority; generated views via MASTER/tools/design_tokens.rb; freshness item in the root TODO.md |
| No decorative gradient; signal colour stays semantic | `NO_DECORATIVE_GRADIENT`, `SIGNAL_COLOR_IS_SEMANTIC` (MASTER/law/css.rb) |
| Duplicate declarations; long transitions | `CSS_DUPLICATE_DECLARATION`, `NO_LONG_TRANSITION` (MASTER/law/css.rb) |
| Contrast | measured with `Deploy::DesignMetrics.contrast_ratio` against the laws.yml states, per the `_dialect_tokens.scss` header |
| Dead CSS, comments as deodorant | MASTER/lib/fix/dead_css_static.rb, `COMMENTS_AS_DEODORANT` (MASTER/law/cosmetic.rb) |
| Rendered visual proof | `bin/operator design` (Fix::DesignLoop with the visual review triangle), RAILS/visual_completion.yml |

A draft `style_laws.yml` from the same session re-declared these rows as a
parallel catalogue. The table above is the answer: one Law system, one token
source, and the check surface that already reads them.

## Real gaps

- **z-index ladder** — no Law names a numeric z-index ban. The candidate is a Law
  proposal through the proper authority process, with bad/good fixtures drawn
  from real drift, not a side file.
- **Raw hex outside token files** — prevented today by generation and the
  freshness check rather than by a detector over hand-written SCSS. Drift found
  in practice is the evidence that proposes the Law.

## Packaging truth

The session's packaging table proposed maps and messenger as namespaces. The tree
disagrees, and brgen/README.md is feature truth: brgen/engines/ holds dating,
maps, marketplace, messenger and radio, and takeaway is nested inside
marketplace.

| Surface | Home today |
| --- | --- |
| Core city feed | brgen host app |
| dating, maps, marketplace, messenger, radio | brgen/engines/ |
| takeaway | brgen/engines/marketplace/engines/takeaway |
| tv | the radio engine (playlist and tv) |
| identity, billing, trust, activity, geo, media | RAILS/__shared (pub5-shared) |

Re-packaging an engine into a namespace is a structural decision owned by
brgen/AGENTS.md and the tree contracts, taken on evidence of name collision or
extraction pressure — not as part of a stylesheet sweep. Every vertical stays one
brgen row in apps.yml.

## The sweep, in the repo's real verbs

1. Observe read-only: `/fix RAILS --dry-run` (scoped narrower per pass), or the
   read-only chain `bin/operator check --scan-only --tree=RAILS`.
2. Sync tokens from the one source: `ruby MASTER/tools/design_tokens.rb
   sync_dialect_tokens`, then `ruby MASTER/tools/rails/build_all_css.rb --check`
   proves the generated views are fresh.
3. Delete first, tokenize second, thin dialects third — one vertical per pass,
   marketplace or dating as the pilot. Each pass is path-scoped and ends in
   `cd RAILS/brgen && bin/ci`, plus a rendered check whenever layout or tokens
   moved.
4. Automation that already exists: `bin/operator design` boots the declared
   apps, screenshots the weakest surfaces, asks the vision model for one layout
   edit at a time, keeps each edit that scores higher as its own commit on main,
   undoes the rest, and pushes nothing.

Proof stays the three: baseline hashes, path-scoped diff, one check that can
fail. A sweep that claims visual correctness without rendered evidence has not
run.

## The eight lenses

Task briefs for a design pass — one lens per pass, or the combined brief at the
end. They bias judgment; the Laws and the checks stay the arbiter.

**DHH — convention over configuration.** One cascade: tokens, shared chrome,
brand, vertical dialect, page. No parallel design system in an engine; a vertical
changes density and one accent, nothing else. Duplicated cards become one partial
in __shared or one in the vertical. Deletions rank above additions: dead
selectors and wrapper divs go before any new utility lands. apps.yml stays
deploy-only; design lives in SCSS and ERB. Proof: bin/ci plus the flat-pixel and
duplicate-declaration Laws clean on touched paths.

**Matz — optimize for the human reader.** Class names say what a thing is, not
how it looks: `listing-card`, not `u-flex-p-3`. Fewer, better-named components
beat utility soup. Comments carry the why the selector cannot; nothing restates
the code beside it. The token file stays boring, complete and generated, so an
app author never reaches for a magic number. Each vertical's dialect reads in one
file. Proof: bin/ci plus a rename pass reviewed by someone who did not write it.

**Snøhetta — a civic place, not a theme park.** The apex feed is the public
square: calm neutrals from the canonical tokens, photography-friendly, legible
wayfinding, the city switcher always findable. A vertical is a room off the
square and keeps the same materials; entry reads as a threshold, not a rebrand.
Every decorative rule justifies itself against the density Laws. Proof: rendered
review of feed, listing and profile, dialect accents the only colour deltas.

**Ando — void, geometry, load-bearing structure.** Negative space is designed
through the spacing scale, not filled by default. Radii come from tokens and stay
small; hierarchy is proportion and contrast, not ornament. ERB structure is as
plain as concrete: cut the divs that exist only to be styled. Audit the apex
feed, a marketplace listing and a dating profile; strip until only load-bearing
structure remains, then tokenize every number left. Proof: before-and-after DOM
depth plus the pixel Laws.

**Dilla — one grid, swing inside it.** The token scale is the quantize grid; the
pocket lives in how surfaces use it. Dense surfaces sit tighter, the apex
breathes, both on the same kit. Character belongs to content, photography and one
accent per vertical, never to broken scales or private easing. Density dialects
are token aliases (compact, regular, airy), not new ramps. Proof: one component
rendered at three densities with no new hex or font-size literals.

**Flying Lotus — layered worlds, one cosmos.** Every vertical is a layer of
brgen, not a guest from another universe. Overlay, drawer and modal map onto one
named layer ladder; motion shares durations and easing tokens; no vertical ships
a private animation kit. Richness comes from composition — shared partials plus
one feature component set per vertical. Proof: the z and motion inventory clean,
conflicting animation CSS deleted.

**Musk — first principles, delete, automate.** Name the physical constraints:
viewport, legibility, touch targets, payload. Rank CSS as load-bearing or cargo;
delete cargo first. One token source, generated views, no dual maintenance. A
rule that is not automated rots — bin/ci, the token freshness check and the pixel
Laws are the enforcement. Track the byte and selector delta per pass. Proof:
bin/ci, token freshness, and the deletion list with numbers.

**Godin — the brand is a promise kept at every pixel.** brgen's promise is the
city as product: local, direct, uncorporate. It holds on the apex before any
vertical looks clever. A dialect that breaks the promise (generic SaaS
gradients, dark-pattern density) does not ship, however tidy its diff. The design
system stays the smallest viable set that keeps the promise everywhere, then
stops adding. Proof: human review of feed, listing and profile against the
promise, plus the pixel Laws.

**Combined brief — one sweep, all lenses, one spine.** Observe with
`/fix RAILS --dry-run`; sync tokens from MASTER/data/tokens.yml; delete first,
tokenize second, thin dialects third, one vertical per pass; proof = baseline
hashes, path-scoped diff, `bin/ci` plus `build_all_css.rb --check`, rendered
review when layout or tokens moved. The voices agree where it matters: one token
source, flat surfaces, deletions first, one accent per vertical, the promise kept
on every surface. The Laws and the checks arbitrate every disagreement.

## What never counts as delivered

- "Tokens aligned" without `build_all_css.rb --check` green on the current
  revision.
- "Vertical dialect thinned" without a rendered feed, listing and profile
  comparison.
- A sweep claimed over paths no diff covers.
- Any pixel claim whose only evidence is the plan.
