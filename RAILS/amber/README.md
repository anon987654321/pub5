# amber

**A wardrobe that knows what is in it, what you actually wear, and what it
is only guessing at.** Amber is Ragnhild's wardrobe app. It holds garments and outfits,
runs the KonMari declutter loop, tracks how taste changes over time, and
explains the basis of its recommendations.

Amber runs Rails 8.2.0.alpha on SQLite behind Falcon, with Hotwire, Active
Storage, Solid Queue and relayd. It listens on port 61352.

## Character

Amber is a personal wardrobe companion, not a fashion shop. Its character
is warm, intimate and evidence-led. The wardrobe is the source of truth; a
recommendation explains itself. The product helps its owner wear and understand
what she already owns before encouraging another purchase.

Toteme is Amber's primary fashion-design reference. Borrow its collection-led
navigation, image-first grids, restrained metadata and clear item-detail
composition. Translate those patterns into wardrobe organisation and wear
decisions, not retail selling. Keep Amber's warm-neutral tokens, original
masthead, sans typography and truthful garment imagery. Do not import another
brand's wordmark, campaign art or exact visual skin.

Design values come from `MASTER/data/tokens.yml` through `Master.tokens`.
The feature matrix is `RAILS/apps.yml`, under `amber`.

The app defaults to Norwegian. The default locale is nb, with en available, and a request picks
its language from a ?locale= parameter, then the session, then Accept-Language, then nb. A
switcher in the footer sets it. Chrome, empty states and flash messages all go through I18n, and
the sentences the shared engine owns, such as not_authorized and rate_limited, come from
shared.flash. Tests assert through keys and never through English literals.

## Visual direction

TOTEME is Amber's primary fashion-design reference; NET-A-PORTER is the benchmark for
catalogue clarity and product-information hierarchy. Borrow collection-led navigation,
image-first grids, generous editorial spacing, restrained metadata and clear item-detail
composition. Translate those patterns into wardrobe organisation and wear decisions, not
retail selling.

The wardrobe is the catalogue. Use consistent garment photography, useful filters, quiet
collection headings and a clear garment detail hierarchy: image, identity, attributes, wear
history, cost per wear and outfit relationships. Recommendations must explain their basis.
Do not add shopping-cart chrome, fake stock pressure, discount language or purchase-first
calls to action. Preserve Amber's original large masthead, warm-neutral tokens and truthful
garment imagery. Align the masthead mark, editorial navigation and look rail to Brgen's shared
`--feed-max` reading measure; Amber's scale and pacing are the variation, not a separate shell.
Amber should feel like a considered fashion editorial, not a retailer.

## Product boundary

Amber is a private wardrobe companion, not a fashion storefront. It helps its owner
understand and wear what she already owns, then supports deliberate decluttering and
selective discovery. Its shipped feature inventory lives in `RAILS/apps.yml`;
aspirational work lives in `RAILS/apps.horizon.yml`. Do not promote planned features
to promises: visual similarity search, garment segmentation, virtual fitting and live
video remain unshipped. OpenRouter powers selected analysis only when configured;
otherwise Amber uses explicit rules and heuristics. A garment fingerprint is a local
CRC32-64 checksum, not semantic image search, and a scheduled style session is not video.

## The wardrobe

An Item is a garment, with its colour, size, material, brand, price, category and photographs,
and it computes its own cost per wear. An Outfit joins items in order. Wear logs, planned
outfits and style preferences record how the wardrobe is used and what the owner says she likes.
A WardrobeItem is not a duplicate of Item: it belongs to one garment and one user and carries
only the condition of that garment in that wardrobe. Analytics counts in SQL, so a large
wardrobe is never loaded whole, and four figures draw the picture without a chart library:
category mix, wear distribution, cost per wear and what sits idle.

Photographs go through WardrobeMediaJob, which makes the variants, gives a portrait one polish
pass and extracts the dominant colour. It does not cut the garment out of its background, and no
segmentation or matting exists in the tree. Upload takes a drag and drop onto the item form.

## The declutter loop

The KonMari loop is complete. A garment gets a joy score, and DeclutterScore folds joy, utility
and fit into one recommendation. A challenge binds a user, an item and a due date, and it ends
completed, skipped or expired. A release candidate gets a last-chance outfit, a final way to
wear it before it goes. The decision routes to a destination and a donation bucket.
DeclutterHygieneJob runs every morning at six, expires overdue challenges and nudges anything
that has sat in the declutter box for thirty days.

## What the intelligence is

The intelligence is heuristic and says so. When OPENROUTER_API_KEY is set, the joy analysis, the
outfit suggestions and the capsule path call google/gemini-2.0-flash-001 through OpenRouter.
When it is not set, which is the usual case on the production box, deterministic rules answer
and the interface states which one did.

TasteRanker blends declared style preferences with joy, wear count, recency and life phase at
fixed weights, so it is a formula and not a learned model. StyleAssistant picks one look a day,
deterministic for each user and date, aware of the weather, and it stores nothing until the
owner saves the look. The weather is open-meteo for Bergen alone, cached for fifteen minutes,
with a failed answer cached too and the connection bounded at two seconds to open and three to
read, because it sits in front of the dashboard.

The scores are targets and not judgements. WardrobeGap compares the closet with a fixed list of
essentials per category. The sustainability score scales and caps wear count and adds a bonus
for joy, and it is not a lifecycle assessment. ClosetOrganization offers care, storage, zoning
and restraint tips, each naming the principle behind it, and WardrobeAnalytics adds its own
nudges. These are rules and the interface labels them as rules.

Two things that sound like AI are not. A garment fingerprint is a local CRC checksum over the
image bytes, which finds a repeated upload and never a lookalike, and EmbedGarmentJob survives
only as an alias of FingerprintGarmentJob so that queued rows still find a class. There are no
embeddings anywhere, and the vector column is JSON because pgvector would require Postgres.
DuplicateDetector follows from that: it groups items on an exact key made from category, colour,
material and brand, so two similar shirts that differ in any of those are not duplicates to it.
Style sessions carry a calendar date and a status and are not video. Shop the Look ranks the
affiliate links the owner added herself, and its remote half needs TRADEDOUBLER_TOKEN, which
lives on brgen, and says so when that half is dark. amber imports no product feed.

## The social side

amber shares the social stack with brgen. It has a feed of posts with comments, reactions,
follows and mutual connections, messages, and scheduled style sessions. Posts that carry a
YouTube, SoundCloud, Vimeo or Spotify link show a player facade, and the lookup waits for the
hourly queue drain, so the plain link shows until then. A creator profile can publish a garment
for others to remix, under the consent rules in the owner's privacy settings, and
WardrobeVisibilityPolicy answers every question of who may view, remix or analyse what. MASTER
can be invited into a message thread. A sign-in from brgen never reaches amber, because the
session cookie is scoped to the registrable domain, and the one door between them is the
MASTER-signed token at /sso/from_master.

Random pairing has a video layer. An Encounter pairs two askers as before; the
RandomVideoChannel now relays the WebRTC dance between the two browsers, coturn relays the
pairs that cannot connect directly, and TurnCredentialService mints time-limited TURN
credentials from one shared secret. The video room and its TURN endpoint sit behind the age
gate: a camera pointed at a stranger needs an age-verified account, the text thread stays as
it was.

## Guests

User carries a guest column, so an anonymous visitor gets a soft Current.user and can use the
product without signing up. For that reason allow_unauthenticated_access is a no-op in amber,
and require_real_user is the identity check that means anything. A demo wardrobe at /demo is
seeded for guests, and Shared::PruneGuestUsersJob prunes the guest rows every night. Guests can
post and message without first creating an account.

## Identity and account continuity

Amber and Brgen use the same registration fields, email-verification policy and shared OAuth
callback. Email/password, Google, Facebook, Vipps and BankID are available when the matching
provider credentials and configuration are present. Email confirmation is separate from explicit
newsletter marketing consent. A high-assurance BankID subject can authenticate without inventing
mailbox proof from a synthetic email address.

When a visitor registers or signs in while a persisted guest owns activity, the shared merger
moves the guest's post/comment ownership and applicable conversation or message history inside
one transaction, records an account-merge audit row, destroys guest sessions, and anonymises the
source guest row as a non-authenticating audit referent before the registered session is created.
An old guest cookie is never promoted into a full account session.
If the merge cannot be committed and audited, the visitor is told that the transfer is blocked
and the guest session remains available for retry; authentication must not silently strand the
activity. The federated-identity and account-merge tables are app-owned migrations in
`db/migrate`, so run Amber's migrations and dump the schema before enabling this path.

## Account deletion

Account deletion sets a 30-day grace period and revokes the active login immediately. Amber's
`UserPurgeJob` is scheduled daily at 03:50. It removes private wardrobe, profile, connection,
identity, session, inbox and account-linked outbound-attribution data; deletes click records tied to private wardrobe objects, purges attachments through model callbacks, and anonymises the
user row. Public posts and comments remain attached to the anonymised row to preserve discussion,
but references to removed wardrobe items/outfits and deleted inbox messages are removed from posts, recommendations,
declutter history, reactions, notifications, votes, outbound-click attribution and moderation
cases so another user's row cannot retain a pointer to erased private data. If a required erasure table is missing or an account cannot be purged, the
transaction rolls back for that account, its deletion marker remains due for retry, and the job
reports the failure rather than marking erasure complete.

## Architecture

Amber owns wardrobe-specific records and services. The shared engine supplies common
identity, authentication, tenancy, media processing and social integration.

- **Identity and privacy:** `User`, `Profile`, `PrivacySetting`,
  `IdentityVerification`, `ConsentEvent` and `CreatorProfile` govern account
  identity, wardrobe visibility, analysis consent and creator remix consent.
- **Wardrobe:** `Item` is the garment. `Outfit`, `OutfitItem`,
  `PlannedOutfit`, `WearLog` and `StylePreference` describe combinations and use.
  `WardrobeItem` joins one garment to one user and stores that owner's condition;
  it is not a second garment record.
- **Intelligence and media:** `TasteRanker`, `StyleAssistant`,
  `OutfitGeneration`, `WardrobeAnalytics` and `ClosetOrganization` use
  declared preferences, wardrobe history and bounded heuristics. The legacy
  `GarmentEmbedding` record is not an active embedding or vector-search pipeline.
  `FingerprintGarmentJob` performs exact local deduplication; no garment matting
  or segmentation pipeline is shipped.
- **Commerce and travel:** `AffiliateLink` stores owner-selected links;
  `PackingList` records trip wardrobes. Marketplace lookups use the bounded
  BRGEN integration, not an Amber-owned product catalogue.
- **Social graph:** `Post`, `Comment`, `Reaction` (one like per person and
  target, not a counter), `Follow` (follower to followee), `Connection`
  (requester to addressee) and `LiveStream` carry the social surface through
  the shared engine's delivery.
- **Linktree, Vipps payments and access:** `LinktreePage`, `LinktreeLink` and
  `LinktreeEvent` record a creator's external link surface;
  `VippsAgreement` and `VippsPayment` carry the Norwegian payment rail;
  `LiveStreamAccess` gates a stream; `WearsWellWith` records pairings the
  wardrobe suggests.
- **Stranger pairing:** `Encounter` is one random-pairing ask; a posted row
  becomes a wait or a match, and a match opens a message thread.
- **Declutter loop:** `DeclutterChallenge`, `DeclutterOutcome` and
  `DeclutterReview` record the KonMari decision, its destination and its
  review; `DeclutterHygieneJob` enforces hygiene on top.
- **Sessions and travel:** `Session` is a signed-in browser for a user;
  `PackingListItem` joins one garment to one trip on a `PackingList`.
- **Creator remix:** `CreatorWardrobeItem` marks a garment a creator has
  remixed into their public wardrobe, under the consent layer above.
- **Sustainability:** `SustainabilityMetric` holds an item's computed
  wear-and-care figures; `CalculateSustainabilityJob` computes them once per
  item and `RecommendOutfitsJob` runs the bounded LLM suggestion pass with
  concurrency limits.

The app's routes and source define the complete model inventory. `RAILS/apps.yml`
remains the authority for shipped feature status; this summary explains ownership.

## Service layer

Where Amber's product intelligence lives, and the layer no document has covered.
All under `app/services/`.

| Service | Role |
|---|---|
| `CapsuleBuilder` | Builds a capsule wardrobe and explains why each item earned its place |
| `DuplicateDetector` | Groups near-identical garments, ranks them, names a keeper and release candidates |
| `WardrobeGap` | Finds missing categories and connectors; writes `Recommendation` rows |
| `OutfitCompatibility` | Scores a combination on category balance, color balance, occasion fit |
| `OutfitGeneration` | Generates outfits from scoped items, layer-aware, biased toward least-worn |
| `StyleEvolution` | Wear timeline grouped into life phases |
| `TasteRanker` | Ranks garments on declared preference plus joy, wear, recency and life phase; `explain` names the reasons |
| `StyleAssistant` | One outfit for today — deterministic per user and date, weather-aware, rests recent wears, persists nothing |
| `ClosetOrganization` | Care, storage, zoning and restraint tips, each naming its principle and the wardrobe evidence behind it |
| `WardrobeAnalytics` | Summary, average cost-per-wear, tips. Counts in SQL — it never loads the wardrobe |
| `WardrobeCharts` | The four analytics figures: category mix, wear distribution, cost-per-wear, idle |
| `WardrobeAi` | Joy analysis and outfit suggestion; reports `available?` and degrades when unconfigured |
| `WardrobeVisibilityPolicy` | Answers view / remix / run-AI-analysis against layer 1 consent |
| `GarmentTaxonomy` | Category normalization, weather fit, formality score, semantic tags |
| `ShopTheLook` | Local affiliate links plus remote suggestions for an item |
| `Weather` | Today's conditions, decoded for planning |
| `DeclutterScore` | Joy, utility and fit into one score and a recommendation |
| `DeclutterActionRouter` | Decision to destination, donation bucket, and user-facing copy |
| `DeclutterDashboard` | Summary, top candidates, decision matrix |
| `LastChanceOutfit` | Final outfit suggestions for a garment about to leave |

Controllers are discoverable from `config/routes.rb`; service intent is not,
which is why services are enumerated here and controllers are not.

### Later host integrations

`Vote` stores user-scoped polymorphic scores. `MasterMessageReplyJob` handles
Amber messages addressed to MASTER through `Shared::MasterMessenger`.
`BrgenCommerce` and `CommerceFit` provide the bounded BRGEN catalogue integration
listed in the service table above.

## Monetisation

The plan that exists is amber premium: EUR 7.99 a month or EUR 69 a year in
`RAILS/__shared/config/plans.yml`, gated by the `amber_premium` entitlement. Premium earns its
keep when the recurring value is real: unlimited wardrobe size, export, multi-wardrobe and the
analytics the free tier only samples. The `/billing` page shows the plan as not yet available
while its Stripe price env is unset, so nobody reaches a checkout that cannot complete. Do not
raise the paywall before import and export work; a wardrobe someone cannot leave is not a
product someone joins.

Beneath the plan sits the entitlement spine: an Entitlement row answers `accessible_by?` for
one gated thing, and a PaymentTransaction records the money fact that granted it. A Post with
a price is pay-per-view (the unlock is permanent), a ticketed style session costs its price,
and a fresh access token carries one seat for an hour. The Vipps rail (ePayment for one-off
charges, Recurring for Norwegian agreements) lives behind `Payments::VippsAdapter`; until its
env is set it is simply unavailable, like the Stripe half. Vipps' own rule holds in code: the
poller, not the webhook, confirms every payment.

Creator pages are public at `/@slug`: the link-in-bio surface counts a page view and a link
click with an anonymized visitor hash and no more. Internal links land behind the normal
access checks; the page is the top of the funnel, never a way around the paywall.

Affiliate income stays elective and disclosed: `ShopTheLook` ranks links the owner added
herself, and its remote half waits on the TradeDoubler token that lives on brgen, and says so
while that half is dark. B2B seats for stylists, theatres and costume departments wait for
roles and invoicing that do not exist yet. Cross-promotion with brgen runs only with
measurement on both sides.

Metrics that decide the next step: weekly active wardrobes, items added per active wardrobe,
week-4 retention, support tickets per thousand users and payment failure rate.

## SEO and growth

amber is a tool, so it ranks on intent, not geography. Pages that win searches describe
problems the product solves today: cost per wear, capsule building, the KonMari declutter
loop, duplicate detection. A page ships with the feature it names; a page for an unshipped
feature is a promise the tree does not keep.

The mechanics the tree carries: `Shared::SitemapBuilder` with the sitemapable concern,
`Shared::SeoKit` for titles, descriptions and social card meta, one canonical domain —
amberapp.art, with registration state owned by `RAILS/apps.yml` — and consent-based remix
pages creators link to themselves. Accessible forms and fast pages are ranking mechanics too,
and the shared engine owns them.

The rules: no brand doorway pages, no invented community size, no silent reuse of private
photos in marketing — a remix page shows a garment only as `WardrobeVisibilityPolicy` answers
— and no indexing of a wardrobe that is not public. Growth loops that exist: guests try the
demo wardrobe at /demo without an account, and registration merges the guest's posts, comments
and message history into the new account; creators publish remixable garments and bring their
own audience with them.

## Running it

amber.sh sources the shared deploy contract and copies the tracked tree at RAILS/amber to
/home/amber/app on vm23, with the pub5-shared engine copied beside it at /home/amber/shared. The
service reads one env file, /etc/amber.env, which needs SECRET_KEY_BASE. Solid Queue clears its
finished jobs hourly. Falcon is started with a long health-check timeout, because on one vCPU
beside master and brgen the app does not boot inside Falcon's default thirty seconds, and a
worker killed at that mark reads as a broken app.

Every deploy of any app sheds amber and bsdports, and relayd keeps answering TLS while amber is
down, so the failure shows as curl 000 and never as a 5xx. Check the port and not the site.
ALLOW_AMBER_DOWN=1 waives the check in deploy-smoke.sh where being down is the policy. The
domain is amberapp.art; apps.yml carries the registration expiry and renewal flag, so read it
there rather than here before pointing anyone at the name.

The Litestream config is inert by decision, because OpenBSD has no binary for it. The backup is
a nightly pull from the operator's Mac with OPENBSD/bin/dr-pull, which checks each database
before it keeps the copy. When a Solid Queue backlog builds, OPENBSD/bin/amber_queue_sweep.sh
clears it with sqlite3, without booting Rails.

## Bringing it up

```zsh
MASTER/bin/operator triangle up amber
curl -fsS http://127.0.0.1:61352/up
doas zsh RAILS/amber/amber.sh
```

## Brand and demo-media references

The following design and asset guidance is consolidated here so Amber has one project entry point.

### Demo media

**The demo wardrobe should show the cloth as well as the cut, so a visitor sees both the shape a
piece takes on the figure and the fabric it is made of.** Each photograph here is one garment or
one outfit laid flat on a single warm backdrop, with no person in the frame, so the clothes are
the only thing that changes from one picture to the next.

The catalogue is default.yml, and it maps a seed key to a file in the images folder beside it.
Today it holds one row, the camel wrap coat. The prompts for seventeen garments and three
outfits are written in STUDIO/lora/seed_media.yml and the other nineteen are not yet
rendered and filed, so most demo items still show only the drawn cut-out. Filing a frame is
enough: the next seed attaches it, and no code changes.

The seeder attaches the drawn cut-out first and the photograph second. The dressing room lays
its zones over the first photo, and the cut-out is drawn for that. The item page shows every
photo, which is where the flat lay earns its place. A key the catalogue does not hold attaches
nothing, and a row whose file is missing is skipped with a warning rather than raised, since one
failed seed blocks every deploy. Setting SKIP_DEMO_MEDIA turns attachment off, and the test
environment never attaches.

The frames are rendered on Replicate and graded by postpro before they arrive here.
install_seed_media.rb in STUDIO/lora/_toolkit files them, and the prompt, model, seed
and preset of each render are recorded in STUDIO/lora/seed_media_manifest.yml.

These graded copies are tracked in git, which is a deliberate exception to the rule against
committing generated assets. That rule keeps build output and renders out of history because
they can be made again from source. These cannot: a render costs money and never comes out the
same twice, and the deploy copies only tracked files to the box, where the seeds read them. So
the app keeps a small copy, and the full renders stay out of git on the machine that made them.

### PROPOSALS — plur1bus plates: eleven directions for the amber® mark

Open `all-plates.html` in a browser: all eleven plates render on one page with the
canonical reference on top and the avatar cuts underneath. Regenerate with
`node generate.mjs` (deterministic, seeded; the glyph outlines and the nine
hairlines are extracted live from `RAILS/amber/app/views/shared/_logo.html.erb`,
so the wordmark and the swoosh geometry cannot drift from the shipped mark).

The brief: eleven radically different plates — bit-reduction, motion graphics,
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

## The eleven plates

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
| 11 | `intro_condense` | **Animated intro** — many become one | A field of ~3 000 monochrome carriers drifts in and condenses into the wordmark (2.9 s), a deterministic ~16 % keeping a dimmer identity as residual individuality; the nine hairlines fade up once the mark has formed; a dozen lime carriers are the sole signal accent; canonical white swoosh clipped inside the glyphs | MASTER `face_interface.stipple` — the `face_dotfield` prototype and `stipple_vocabulary` in `tokens.yml`: density is belonging, luminosity is attention, residual individuality survives, motion is a state change not decoration; `motion.reduced_motion_must_preserve_meaning` pins the assembled mark under `prefers-reduced-motion`; the assembled mark is the base state, so a still frame reads |

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
  all-plates.html      all eleven plates + reference + avatar cuts on one page
  README sections      research and proposal notes
  plates/*.svg         11 plates + reference-original.svg
  plates/avatars/*.svg 3 alpha-transparent avatar cuts
```

Home rationale: the logo is owned by Amber, so its generator, previews and research live beside the app. No candidate replaces the production logo until it is selected. The plates are brand documentation, not production assets; rendered PNGs stay out of the repo and the SVGs remain the source of truth.

### RESEARCH — plur1bus plates

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
direct homage; plate 07 is a separate seeded star field, not a motion-frame treatment.

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
