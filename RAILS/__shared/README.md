# Shared Rails engine

**One engine lets four products speak a shared interface language without
looking alike.** Brgen, Amber, BSDPorts and MASTER's face share layout and
interaction rules; each keeps its own visual dialect. The `pub5-shared` gem supplies layout
chrome, accessibility defaults, social primitives, a service worker and
vendored Stimulus components. Apps load it by local path.

The design values do not start here. They are declared in `MASTER/data/tokens.yml`,
and the `design_tokens.yml` beside this README is a file generated from it by
`ruby MASTER/tools/design_tokens.rb sync_dialect_tokens`. Edit the source and regenerate, and
never hand-edit the projection. MASTER's browser face is assembled from ordered
source modules in `MASTER/web/styles/face/` by
`MASTER/tools/rails/build_face_css.rb`; edit those modules rather than the public
bundle. Its `:root` block is still generated from the canonical tokens.

Every HTML document inherits one chrome contract:

- The viewport respects the safe area.
- The first focusable element is a skip link to the main content.
- The `main` element has an id and its required role.
- Primary controls meet the minimum tap target height.

A product may restyle colour, type and radius. It may not invent a second
z-scale, skip link or tap-size standard. The interface is flat: no shadows,
blur or hairline rules. Space separates components. Form fields retain an
outline so users can identify their input targets.

The dialects are deliberate. brgen and its verticals wear a grayscale called
brgen_old, with a per-vertical accent. Amber wears warm paper and its own editorial
faces. BSDPorts is an ultra-minimal white search surface inspired by the classic
Google front page: Arial, blue result links, neutral grey metadata, and compact,
flat geometry. Its `wscons` body class remains a compatibility hook for flat and
square shared-component rules; it does not define a dark palette. The face is black
with lavender, square, in a monospace. The theme is one mechanism everywhere:
shared `theme_toggle` and `theme_bootstrap` partials write the theme onto the
document element, and the stylesheets read it from there. Declared is not worn, so
read the built bundle before you describe what an app paints. The typeface is the
same family in every app, and a fifth face is a decision and not an accident.

Three of those decisions have been taken, on the operator's word (2026-10-29 and,
delegated, 2026-10-31), and are recorded so that no one reopens them as drift:

- **Amber's primary fashion reference is Toteme.** Use it as a close structural
  template for collection-led discovery, restrained navigation, image-first grids,
  consistent product-image wells, quiet metadata, useful filters/sort, and a clear
  product-detail gallery beside its facts. Translate those patterns into a private
  wardrobe: lifecycle/category/usage filters, garment facts and wear actions replace
  retail price, seller and checkout mechanics. Amber remains wardrobe intelligence,
  not a fashion shop. Its existing warm-neutral luxury tokens, Helvetica Neue Pro
  sans stack, original masthead and truthful garment colours remain authoritative;
  no copied wordmark, campaign art, typeface, product photography or exact brand skin.
- **Marketplace and Takeaway use bol.com and Kaufland.de as close commerce templates.**
  Borrow their information architecture and interaction patterns: prominent search,
  hierarchical category navigation, shortcut rails, filter groups and counts, useful
  sort controls, scannable result grids, a stable price/title/rating/facts hierarchy,
  and media beside a decision-ready detail/buy box. For Marketplace, the facts are
  price, seller, locality, condition, delivery and offer/cart actions. For Takeaway,
  adapt the same grammar to restaurant discovery and menu ordering: cuisine, truthful
  open status, delivery fee, minimum order, ratings, dish price, dietary/allergen
  facts, quantity and one clear order action. Never invent availability, ratings,
  delivery promises or scarcity.

  These are user-selected structural templates, not permission to reproduce the
  references' logos, wordmarks, campaign art, photography, copy, distinctive
  typography or exact branded visual skin. Brgen retains its deep-blue city identity,
  local voice and city-first product logic. The store dialect retains its current
  1px field and tile rules, corner radii and commerce sans
  (`--font-commerce-sans`, a Helvetica Neue stack). This is the named exception to
  "flat, no hairline rules" and to the one family, scoped under
  `body.vertical-marketplace`. It does not travel to any other surface.
- That dialect is two layers in brgen's stylesheet, the Kaufland `--store-*` rules
  and the later bol `--bol-*` rules. Where both set one property the later layer
  wins, so a rule meant to hold in both is written in the bol layer. The category
  grid showed five tiles beside a column sized for four for exactly that reason.
- Motion that is the operator's own design ships as designed, with its library
  vendored and a still state for reduced motion and for no script: dating's first
  screen (a css-doodle heart over a red bloom, the one gradient on a dark ground),
  the marketplace's animated logo (anime.js) and brgen's in-feed collage ad.
  Amber's affiliate rail stays the calm catalogue.

Each app compiles one stylesheet, `application.scss`, into one built
`application.css`, and a layout links that file and nothing else. The brgen
verticals style themselves inside brgen's, scoped under their vertical class. The
app begins by loading the engine's `stack`, which forwards the minimal base, the
tokens, the animations, the buttons and the components, and then writes its own
rules below. The button partial's position is a cascade contract and not an
ordering convenience.

On the Ruby side the engine holds the concerns that models and controllers share:
reactions, votes, comments, notifications, activity tracking, geolocation, strict
safe associations, live search and attachment limits. Strict loading is on in every
environment, so a method that writes first and then reads a lazy association can
commit the write and then raise. The safe-association helpers exist for paths where
a lost notification is worse than an extra query, and they are not a licence to
skip preloading. The engine also owns the password mailer, the mailer layout and
the fingerprints controller. Framework-required host constants stay in each app as
thin wrappers, because routing and the autoloader resolve them by bare name.

On the JavaScript side, `frontend/hotwire.js` and `frontend/stimulus_boot.js` are
the entry points. The Stimulus components are vendored, never fetched from a CDN,
and the stimulus components check holds that line. Plain HTML must work without
scripts, so every live search ships server-rendered content and its loading, empty
and error states. Toggles answer with a redirect, and Turbo's morphing refresh makes
that cheap.

Some decisions are recorded so that no one reopens them. An agent may not choose or
change a rendered value: a colour, a radius, a breakpoint or a layout belongs to
the operator. The agent may add a token that holds an existing value, add a check, or
repair an ambiguity, and then must say so in the commit. Pages that carry
per-viewer chrome are never cached for everyone. Nothing is preloaded or
pre-connected beyond what is there, because the box has one core and 1 GB. Findings
against the design system are often findings against the instrument, so check what a
number measured before you believe it.

The surveys of past UI work sit beside this file: the layout and surface refinement
matrices, the social front page and the two archaeology notes. They are records, not
contracts. The three `*_micro_refinements*.scss` sheets are intentionally excluded
from both production stacks until each proposed change has rendered before/after
evidence and explicit operator approval. A count of CSS declarations is not a quality measure.

## Vipps brand assets

The shared engine carries two official Vipps wordmarks for the apps that use
its payment and login surfaces:

- `app/assets/images/vipps/vipps-wordmark.svg`: orange wordmark for light
  backgrounds, sourced from the
  [Vipps WooCommerce merchant plugin](https://github.com/vippsas/vipps-woocommerce/blob/052b7fd57365ec9c68e91a7b60df7af210bb61d2/payment/img/vipps-rgb-orange-pos.svg).
- `app/assets/images/vipps/vipps-wordmark-on-orange.svg`: white wordmark on
  the Vipps-orange block, sourced from the
  [negative merchant wordmark](https://github.com/vippsas/vipps-woocommerce/blob/052b7fd57365ec9c68e91a7b60df7af210bb61d2/payment/img/vipps-rgb-orange-neg.svg).

Both are retained unmodified. Do not recolour or stretch them; replace them
with the restaurant or merchant's supplied brand-kit files when the applicable
merchant agreement provides them. Mr. Damascy is not on this shared engine and
keeps its own wordmark copy.

## External page extraction

`Shared::Scrape` is an outbound-network boundary, not just a browser helper. It accepts
public HTTP(S) entry URLs only, refuses local/private/reserved address ranges and hostnames,
and rechecks every browser request so redirects and embedded resources cannot point at
loopback or cloud metadata. DNS answers containing even one blocked address are refused.
This application guard complements host-level egress/firewall policy; it is not a substitute
for it. The public/private target contract is tested in
`RAILS/brgen/test/services/shared_scrape_test.rb`.

## Checking it

```zsh
ruby RAILS/test/layout_contract_test.rb
ruby RAILS/test/layout_contract_surfaces_test.rb
ruby RAILS/test/design_contract_test.rb
ruby RAILS/test/design_contract_components_test.rb
ruby MASTER/tools/rails/build_all_css.rb --check
ruby MASTER/tools/rails/build_face_css.rb --check
ruby MASTER/checks/runner.rb stimulus_components
ruby MASTER/checks/runner.rb frontend_auditor
```

## Fonts

The RAILS shared engine serves these assets from `/fonts`. The CSS makes no third-party font requests.

## Source Sans 3

Proportional sans serif variable font, weights 200 through 900, normal and italic.

- Upstream: https://github.com/adobe-fonts/source-sans
- Files: `WOFF2/VF/SourceSans3VF-Upright.ttf.woff2`, `WOFF2/VF/SourceSans3VF-Italic.ttf.woff2`
- License: `SourceSans3-OFL.txt` (SIL Open Font License 1.1).

JetBrainsMono Nerd Font is the one bundled monospace face (`--font-mono`).

## JetBrainsMono Nerd Font in terminal emulators

The shared engine serves regular and bold WOFF2 faces to browser CSS. PuTTY
and Termux need a native fixed-width font installed on the device; they cannot
use the web WOFF2 assets as their terminal font. Install the JetBrainsMono
Nerd Font TTF/OTF build locally and select it in PuTTY's Window → Appearance
font picker or Termux's More → Style → Choose Font menu. Termux can load a TTF
from ~/.termux/font.ttf; run termux-reload-settings after changing it.

The [official Nerd Fonts JetBrainsMono release archive](https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.tar.xz)
contains the native TTF/OTF variants, including the Mono build. Select that
installed face in PuTTY or Termux.

The WOFF2 assets are web projections, not an installer for the operating
system or terminal. MASTER never changes the emulator's font or size.

Keep the license text with the font binaries in source distributions and deployments.

## Shared social front page

Updated 2026-09-30 after a current review of Reddit, X and TikTok, with the goal of taking interaction patterns rather than copying their surface styling.

## Consent

The useful pattern is not a louder "accept" button. It is a short explanation, equal first-layer choices and an easy path to preferences. X documents a broad stack of cookies, pixels and local storage for authentication, preferences, personalization, analytics, advertising and related functions. It also documents extra controls for off-X activity and personalization. TikTok likewise exposes cookie and advertising measurement controls in its privacy tooling.

Pub4 already had the right core behavior: optional analytics and advertising stay off until consent, with accept/reject/manage peers. The integration adds an explicit necessary-storage row so the reader can see what is essential and what is optional.

## Onboarding

Reddit's own guidance stresses that a new visitor should understand a community through clear descriptions, rules, welcoming material and posting guidance. X's signup sequence asks for account setup, then interests/accounts, then posting. TikTok's main product loop is the For You feed: the user starts watching and recommendations learn from engagement.

The pub4 implication is simple: do not put a long setup wizard between a visitor and the product. The existing welcome cover remains the deliberate first-run story, with three concrete steps, persistent dismissal and consent-aware ordering. MASTER now treats "show the product before asking for setup" as a durable constraint.

## Content

Reddit supplies contextual community identity and multiple feed interpretations. X compresses a post into identity, statement/media and a compact action row. TikTok reduces the cognitive load further by letting the media itself become navigation and by continuously adapting what comes next.

For brgen this argues for a feed that feels locally alive before it feels like a dashboard. The existing city feed, staged live arrivals, media wall and vertical promotional units already provide the building blocks. The new post-detail action jump makes the conversation immediately reachable without adding another feed-ordering strip to root.

Amber should keep its editorial reading posture rather than imitate a generic social feed: richer whitespace, wardrobe/item context, then action and discussion.

## Post detail and auth

The strongest small pattern from X is a focused auth interruption that preserves the current context. X documents that its follow widget shows a small pop-up when used by logged-out visitors, rather than requiring the widget host page to become the account page.

Pub4 now uses the browser's native Popover API for the same class of interaction on brgen and amber post detail pages. It offers sign in and account creation in a compact surface while leaving the post readable. Native popover avoids another bespoke modal state and keeps focus, escape and top-layer behavior with the browser.

Brgen also exposes the existing comment count as a direct jump from the detail action row. The page remains content-first, while social proof and discussion are only one small gesture away.

## Small details worth keeping

Use the browser's native overlay primitives where they fit. Keep 44px interaction geometry
(shared_chrome.tap_min in MASTER/data/tokens.yml), visible focus, one reading measure, no
duplicated nav, staged live arrivals, and explicit sponsored labeling. Avoid copying colors,
gradients, radius values or visual chrome merely because another service uses them; those values
remain owned by the pub4 design system and its operator.

## Primary sources

Reddit:
- https://support.reddithelp.com/hc/en-us/articles/53416317564820-Changelog-September-10-2026
- https://support.reddithelp.com/hc/en-us/articles/28621027395220-How-to-join-or-leave-a-community
- https://support.reddithelp.com/hc/en-us/articles/15484358732692-Welcoming-new-members
- https://support.reddithelp.com/hc/en-us/articles/45959071783316-Changelog-February-4-2026

X:
- https://help.x.com/en/using-x/x-timeline
- https://help.x.com/en/using-x/create-x-account
- https://help.x.com/en/rules-and-policies/x-cookies
- https://help.x.com/en/using-x/add-follow-button-to-website
- https://help.x.com/en/rules-and-policies/recommendations

TikTok:
- https://support.tiktok.com/en/getting-started/for-you/test-for-you
- https://newsroom.tiktok.com/new-features-bring-tiktok-magic-to-desktop?lang=en

## Shared live-post contract

Brgen and Amber share one social-post anatomy: `shared/post_card` owns the post's reading structure and `shared/post_vote_rail` owns its vote controls. The app partials provide the facts and actions that belong to their own product. Brgen remains the local, community-aware stream; Amber remains the editorial, wardrobe-aware reading surface. A shared card is not a shared front page.

The card's root is also a stable interaction boundary: its `article.feed-card.post-reading-card` carries `data-post-card="true"` and `data-post-id="ID"`. Future controllers can scope updates to one post without relying on title text, list position, or a broad feed selector. These attributes add no client-side state and do not turn the generic entity card into a social post.

The card's live targets are deliberately small and stable:

- `data-post-score="post_ID"` is the score value.
- `data-post-like-count="post_ID"` is the like count.
- `data-post-comment-count="post_ID"` is the comment count.
- `data-post-repost-count="post_ID"` is the shared repost count.
- `dom_id(post, :vote_rail)` is the current reader's vote-control region.

A count update changes only its text target. A vote replaces only the vote rail belonging to the reader who submitted it. A like replaces that reader's like button and broadcasts the new shared count. A repost or undo updates only the shared repost count; the local request returns that reader's pressed state, and the broadcast never carries another reader's button. Do not broadcast a complete post card containing another reader's pressed states, ownership actions, or moderation controls.

The event boundary matters as much as the markup:

- A vote changes the stored score and broadcasts the counter values; it does not touch the Post and must not refresh every open feed.
- A like updates its reader's button and broadcasts the shared like count.
- A comment updates the global feed's count and refreshes only the affected post's detail stream. The detail thread is rendered again for each subscriber, so reply, delete and report controls are evaluated for that reader.
- A real post-content edit or other card-changing mutation still refreshes the card/page. Related item or outfit changes must not be mistaken for a counter-only touch.
- Brgen's city feed keeps its existing staged-arrival protocol: new cards wait in the hidden pending region until the reader chooses to reveal them. Amber keeps its editorial front-page rhythm; it does not inherit Brgen's city-arrival chip simply for sharing the post renderer.

Brgen's vote, comment and repost counters are emitted by their own commits. A post vote updates the score with SQL and broadcasts the score target; it does not touch the Post row or invalidate its cached card. A post comment moves the counter cache and broadcasts the count; a repost moves its counter cache and broadcasts that count. Neither touches the Post row. The polymorphic associations preserve touch behaviour for non-post records, so event/item/outfit activity is not silently changed by the social-post optimization.

`shared/feed_card` remains the generic entity-card primitive for communities, channels, shows, matches, orders and other vertical records. It is not a second implementation of the social-post card. Marketplace listings, dating profiles, live video, maps, takeaway restaurants, ports and order flows keep their own content hierarchy and primary interaction.

Future post capabilities should extend the existing shared card through explicit data/slots and narrowly scoped stream targets. Prefer one event with independently replaceable facts to a full-card redraw; prefer a server-rendered reader-specific control replacement to optimistic state that can lie after a failed request. Keep the feed useful without JavaScript, respect reduced motion, preserve stable IDs, and test both the markup contract and the stream destinations.
