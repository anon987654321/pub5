# Handoff — pub5 / brgen completion — 2026-11-22 — next agent

Status: proposal-grade implementation brief. Session evidence under the receipts
precedent (MASTER/data/receipts/fix-session-2026-11-19-grok.md and
fix-session-2026-11-22-qoder.md), authorised by the operator's explicit request
for a new handoff. It consolidates sections A-U of the intake receipt into one
executable brief; the intake receipt remains the evidence log. This file creates
no backlog authority: every slice routes to its owning registry (gaps.yml,
apps.yml, convergence.yml, operator_seams.yml, ideations/, ux_refinements.yml,
RAILS/refinements.yml, proposals.yml). Re-measure before acting; a finding is a
hypothesis. No Ruby suite, rake task, Law detector, /fix lane or browser check
ran in the intake session (no Ruby >= 3.2, no Chrome, no deploy host in the review
sandbox); all such proof is NOT_RUN until you run it on a compatible host.

## 0. Read first, in this order

1. MASTER/data/soul.yml — highest authority: identity, preservation, source
   precedence, absolute.sacred_paths (empty by the 2026-11-09 decree, but soul.yml
   and laws.yml stay operator-owned for autonomous writers).
2. MASTER/data/laws.yml — the Law catalogue. For every Law you touch read its
   statement key, its law_catalogue.entries row (severity/mode/lifecycle/autofix/
   languages/surfaces/path_exclude), its Law.define in MASTER/law/*.rb, its
   fixtures or proved_by test, and the focused tests. 554 catalogue entries;
   196 ALLCAPS statement keys; 34 bare roots.
3. Run: ruby MASTER/tools/agent_context.rb --json (add --tree for cross-tree
   work). Consume conduct, blocking_rules, coverage, task_contract_schema,
   capabilities. This is the live brief, not a replacement for reading Laws.
4. MASTER/AGENTS.md — the full contract, especially "Refused, and why" and
   "Do Not Touch". Root AGENTS.md is generated from its marked block; verify with
   cd MASTER && rake lint:agent_contracts (intake found them byte-equal).
5. MASTER/data/law/TREE_CONTRACTS.md — the five-tree acceptance matrix.
6. The owning tree/product entrypoint: RAILS/CLAUDE.md, RAILS/README.md, the
   target app/engine README and any local AGENTS.md.

Authority order: soul.yml > laws.yml > executable laws and gates > tree contracts
> Git history. Git history is provenance, never an override.

### Refused (do not propose or build these)

No TUI; no third surface (MASTER is bin/master + the face); no external agent
protocol (ACP/A2A/OpenAI-compatible /v1); no parallel change streams (one
checkout, straight to main, no worktree/branch/PR); no second language in the
MASTER runtime (Prism is stdlib; no tree-sitter/Herb/Python); no RBS/Steep yet;
no performance machinery ahead of measured slowness; no telemetry/score/check
without a reader; no golden traces or golden renders for model output or dilla;
no detector/index/corpus without a subject; no audit without a path; no
documentation outside its boundary (one README per boundary; no new Markdown —
polish_policy.yml no_new_markdown); no unreviewed self-modification of soul.yml/
laws.yml; no RAILS stack import (Kamal/Thruster/Docker/Inertia/Vite/ViewComponent/
Lookbook/Cucumber/Percy/Chromatic/Playwright; frontend is importmaps/ERB/Stimulus/
Turbo; visual_contract + layout_snapshot are the one paint and one layout
baseline); no two-tower feed / neural ranker / pgvector on the 1 GB SQLite box
(the portable result is a SQL union in RAILS/apps.horizon.yml); no serif for
brgen/amber/master; no covert room listening; no capability adapter without
PersonalPermissions.

### Operator standing preferences (this work)

All new code and tooling in Ruby; all new shell scripts in zsh with strict mode
(ROBUSTNESS_strict_mode_zsh); replies and docs in Strunk & White English;
screenshots for visual work saved under RAILS/*.png or .webp (run-scoped, never
reused); logs published to gists or command-line pastebins (the runtime publishes
redacted log0 to pste.us, dpaste.org fallback; MASTER_LOG_PUBLISH=0 keeps local);
frequent small coherent commits with run vs NOT_RUN stated honestly.

### Commit and delivery protocol

One checkout; path-scoped commits straight to main; never force-push; never
git add -A or git commit -a. Prefer bin/operator land -m <msg> <paths>. Commit
shape (MASTER/data/commit_format.yml, enforced by .githooks/commit-msg):
capitalised subject <= 72 chars, no type prefix, no trailing full stop; body with
the numbers; Co-authored-by trailer. Before push: git log origin/main..HEAD names
what goes with you. After push: git log origin/main..HEAD empty proves delivery;
report DELIVERY_FAILED if the push cannot be proved. Install hooks first on a
real host: bin/operator hooks (sets core.hooksPath). pre-push runs boot_smoke and
the session ledger; a fresh clone has no hooks until installed.

## 1. Bootstrap (exact commands)

In a container with no Ruby/Chrome/libvips/root:

    MASTER/bin/sandbox-bootstrap          # builds vendored Ruby, bundles every
                                          # tree, libvips .deb closure, Chrome for
                                          # Testing; --dry-run prints the plan
    . MASTER/bin/sandbox-env              # source in the shell that follows
    # on a machine that already has the stack, skip bootstrap

With Ruby >= 3.2 (the shared floor; no patch-level pin is authoritative):

    cd MASTER && bundle install
    MASTER/bin/operator doctor            # checkout/host readiness (read-only)
    MASTER/bin/doctor                     # MASTER runtime/provider/voice readiness
    ruby MASTER/tools/agent_context.rb --json
    bin/master '/fix --dry-run --critique --only critique,map MASTER/lib/cli'
    # read veto, INCONCLUSIVE and skip lines as failures of proof, never success

Rendered evidence path:

    MASTER/bin/operator browser install
    MASTER/bin/operator visual sweep APP --one-page     # then the full sweep
    MASTER/bin/operator test PATH                       # smallest isolated proof
    cd MASTER && MASTER_TEST_JOBS=1 bundle exec rake test   # full MASTER suite

Repair vs verification: /fix [path] is the canonical repair loop (observe, repair,
re-observe, scope-selected proof). bin/fix-here TREE wraps it (disk/parse/provider
preflight, per-tree log, stall handling, RAILS lifecycle; --dry readiness only,
--dry-run read-only preview, --no-publish local commits). bin/check is the
profile verification runner (operator default, ci floor, full release); bin/ci is
compat for bin/check --profile=ci. bin/operator check is the repo-wide
Operator::CheckChain ladder (writes fixes by default; --scan-only to measure).
Do not append bin/check --profile=full after every /fix.

## 2. Measured intake facts (instrument named; re-verify on your host)

    HEAD at intake        6d9d498 (main advanced concurrently during the session)
    agent contract        root AGENTS.md == MASTER/AGENTS.md block (byte-equal)
    laws.yml              parses; 554 catalogue entries: 279 warning / 176 info /
                          98 error / 1 veto; 79 automatic autofix / 26 never;
                          16 trusted / 8 advisory / 4 retired
    laws_index.json       fresh at intake (rev 61330272 ancestor of HEAD; no
                          laws.yml commit after it; law_count 554). Re-verify.
    self_findings.yml     31585 findings / 145 rules. Top: rubocop 4583,
                          LONG_LINE 4582, reek 4086, VERTICAL_BREATH 2289,
                          CONSECUTIVE_BLANK_LINES 2200, TRAILING_WHITESPACE 2168,
                          TYPOGRAPHIC_GRID 1711, QUOTES_BY_LOCALE 1566,
                          PREFER_TAG_HELPERS 886, SMALL_FUNCTIONS 812,
                          FEW_ARGUMENTS 650, LONG_PARAMETER_LIST 468,
                          CYCLOMATIC_COMPLEXITY 447, ABC_SIZE 392,
                          NARROW_SILENT_RESCUE 176, MAGIC_COLOR 143,
                          SILENT_RESCUE 125, NO_CHANGELOG_COMMENT 87,
                          CONFIGURATION_SHAPE 87, REDUNDANT_CORE_REQUIRE 85,
                          DATA_CLUMPS 78, STIMULUS_PROGRESSIVE 68,
                          NO_SPACED_EM_DASH 263, NO_LOGIC_IN_VIEW 243
    FACE_WORLD.md         core block repeated 6x at offsets 292, 11762, 23091,
                          33926, 44762, 55597; ~2/3 of 88 KB near-duplicate;
                          later copies carry edits the first lacks
    shebangs              297 tracked: 187 ruby, 43 zsh, 27 ksh, 24 /bin/sh,
                          5 env sh, 2 bun, 2 falcon-host, 1 node, 1 expect,
                          1 termux bash, 1 termux sh, 1 env bash,
                          1 /usr/local/bin/ruby, 1 /bin/zsh
    exec-bit bugs         102 shebang files committed mode 100644 (incl.
                          MASTER/bin/master-session, checks/runner.rb,
                          tools/boot_smoke.rb, tools/polish_lens.rb,
                          tools/security_sweep.rb). AGENTS.md documents this class.
    YAML                  0 safe_load failures across MASTER/data + checks/data
                          (syntax only; Ruby psych semantics NOT_RUN)
    whitespace            0 CRLF; 7 trailing-ws files: data/laws.yml,
                          data/structural_recipes.yml, law/surface.rb,
                          test/test_dialogue_rubric.rb, test/voice/test_voice_support.rb,
                          tools/portal_agent.rb, web/public/three.face.module.js
    final newline         5 missing: axe.min.js (vendored, leave),
                          autopoietic_components.json, coverage_map/state.json,
                          laws_index.json, face_music_packs.json
    .editorconfig         carries a [*.py] block; zero .py files tracked
    MASTER census         3154 tracked files, 921 test files, 914 lib/*.rb,
                          32 law/*.rb, 146 tools entries; checks.yml 72 checks
    convergence.yml       82 workstreams; ops_alert_channel the one "missing"
    operator_seams.yml    67 seams, all open, each names needs/evidence
    gaps.yml              54 gaps; statuses open/picked/blocked/satisfied
    dup_census.yml        161 duplicate sets (mostly intentional; triage below)
    lanes.yml             codex-cli and gemini marked dead

## 3. Rendered-evidence findings (measured from committed captures; STALE)

Instrument: read MASTER/checks/data/layout_snapshots/brgen-*-mobile.json (rendered
geometry) and analysed MASTER/checks/data/route_screenshots/brgen/*.png with
PIL/numpy. These are prior-revision baselines; rails_stale_capture_source_reconciliation
is an open seam. The home PNG (__loopback__390.png) is DARK (#000000/#16181c,
#e7e9ea text, #1d9bf0 blue) while marketplace/dating/takeaway PNGs are LIGHT
(#efefef/#ffffff, #1e40af); the home snapshot reports a light tab contradicting
its own dark PNG. Captures are mutually inconsistent. NONE stands as the current
design. Take a fresh sweep (section 1) before any design PASS.

Concrete findings, bounded to the captured revision, with exact owners:

3.1 Title duplicates the city. Rendered: brgen core "Bergen - Bergen";
    marketplace "Markedsplass - Bergen - Bergen"; other verticals correct
    ("Dating - Bergen", "Restauranter - Bergen"). Investigate:
    RAILS/brgen/app/views/layouts/application.html.erb (the <title> assembly),
    RAILS/brgen/app/helpers/application_helper.rb (city_name = Current.city_name;
    the comment "pages.home_title was the literal ... interpolate this rather
    than name a city"), and the nb/en locale pages.home_title. Root cause is the
    city appended to a title that already carries it. Intent content_only;
    preserve every other title; prove with a rendered <title> assertion per
    surface + the locale tests.

3.2 Active tab text fails contrast on six verticals. The tab label uses
    tokens.yml#tokens.vertical_accents.<v>.light on #f9f9f9 at 18px normal text.
    House target normal_text_contrast is 7.0 (typography.accessibility); WCAG AA
    is 4.5. Measured against CURRENT tokens:

        vertical     tab colour   contrast on #f9f9f9   AA 4.5   house 7.0
        marketplace  #1E40AF      8.28                  pass     pass
        tv           #dc635c      3.33                  FAIL     FAIL
        dating       #009579      3.58                  FAIL     FAIL
        takeaway     #c26a30      3.69                  FAIL     FAIL
        playlist     #0e8a94      3.93                  FAIL     FAIL
        maps         #5585c5      3.60                  FAIL     FAIL
        messenger    #6b7fd7      3.54                  FAIL     FAIL

    (marketplace's snapshot showed #98876e 3.31 — stale; current blue passes.)
    Owners: RAILS/brgen/app/views/shared/_mobile_chrome.html.erb (#app-tab-bar,
    .tab-item, aria-current="page"), RAILS/brgen/app/assets/stylesheets/
    _brgen_navigation.scss (the active-tab colour binding), tokens.yml
    vertical_accents + vertical_accent_ink (#110f19). Fix options, each verified
    per vertical, operator gates the rendered colour:
      (a) add an accessible tab-text token per vertical derived to >= 7.0 on
          #f9f9f9 (house target), falling back to >= 4.5 minimum;
      (b) active tab = accent FILL + ink text; ink #110f19 on accent measured:
          tv 5.41, dating 9.94, takeaway 6.38, playlist 7.70, maps 5.72,
          messenger 5.10 (all >= 4.5) but marketplace 3.67 FAILS — marketplace
          needs light text on its blue; verify each pair before choosing;
      (c) active label >= 18.66px bold to use the 3:1 large-text rule; verify.
    Prove: rendered contrast check + accessibility_axe + keyboard_flow at
    390/768/1280, before/after screenshots under RAILS/*.png.

3.3 Body/input text below the 16px minimum. Snapshot font_size 15.8px on nav,
    search and buttons; typography.accessibility.body_min_px = 16 and
    mobile_input_min_px = 16. Owners: _brgen_navigation.scss, the search partial
    RAILS/brgen/app/views/shared/_search_palette.html.erb, button styles. Raise
    to >= 16px (inputs especially, to avoid iOS zoom). Prove rendered + axe.

3.4 Search field touch height 40px < 44 minimum (REACH_touch_target_min) on
    marketplace and takeaway (#topHalf>div.search.marketplace...). Owners:
    RAILS/brgen/app/views/shared/_storefront_nav_bar.html.erb,
    engines/marketplace/app/views/marketplace/_nav_bar.html.erb, the search
    styles. Raise to >= 44px (48 recommended). Prove rendered geometry.

3.5 Structural skeleton is sound: h1_count = 1, landmarks main/nav/skip present,
    scroll_width == viewport (no horizontal spill) at 390, most interactive
    targets >= 44px, body contrast passes. Keep these green as you change surfaces.

## 4. The execution program (ordered slices)

Each slice: state a TaskContract (MASTER/data/task_contract.yml, validated by
Master::Fix::TaskContract) with intent (content_only / content_and_structure /
functional_change / redesign), repository-relative scope, mandatory preservation
dimensions, proof, and new_paths justified only by a distinct responsibility
(existing-first). Implement under the nearest existing owner. Prove locally
(focused tests + changed-line Law assessment), then rendered where visual, then
the named live seam. Record RUN / NOT_RUN / INCONCLUSIVE. Commit path-scoped, push,
verify. Route the registry row. Operator gates rendered values, copy voice, money,
live hosts, consent.

### Phase 0 — quick wins (land first, one commit each)

0.1 .editorconfig: delete the [*.py] block (zero .py tracked). Proof: doc lint.
0.2 Generated JSON final newline: fix the WRITERS of autopoietic_components.json,
    coverage_map/state.json, laws_index.json, face_music_packs.json (not the
    artifacts); add a newline assertion to checks generated_asset fixtures. Leave
    vendored axe.min.js bytes; record its vendor exemption with a freshness date.
0.3 FACE_WORLD.md dedup: diff the six segments (offsets in section 2), keep the
    union of unique lines, one canonical block, preserve every rendered-value
    decision. Intent content_and_structure. Prove: section-count assertion +
    editorial review. Largest single editorial win (88 KB toward ~30 KB).
0.4 Exec-bit triage: for each of the 102 mode-100644 shebang files find the
    caller. Direct exec (system/spawn path as argv0, shell) needs the bit:
    chmod +x && git update-index --chmod=+x. Interpreter invocation (ruby path,
    bundle exec ruby path) does not — pick one convention (set bit or drop
    shebang) and write it into the shell law fixtures. Start with
    MASTER/bin/master-session (bin/ scripts broke boot silently before). Extend
    test/test_entrypoint_requires.rb to assert every direct-exec entrypoint is
    100755 in the index. One directory slice per commit, boot proof after.
0.5 Trailing whitespace: trim law/surface.rb, tools/portal_agent.rb,
    test/test_dialogue_rubric.rb, test/voice/test_voice_support.rb,
    web/public/three.face.module.js, data/structural_recipes.yml — one commit
    each, focused test after, parse-verify YAML. Report data/laws.yml whitespace
    to the operator (operator-owned; a human commits the trim).
0.6 Dead-lane probe: probe codex-cli and gemini (lanes.yml) via /doctor keyless or
    the lane probe; remove an entry only when the lane answers; record the answer.
0.7 Title duplication (3.1), tab ink (3.2), 16px minimum (3.3), search height
    (3.4): each a slice with fresh rendered proof. These are the highest-value
    visible fixes; do them after a fresh sweep establishes the current baseline.
0.8 incidents.yml "in-tree citation pending" rows: supply the citation or keep
    the honest provenance string; never invent a reference.

### Phase 1 — the shared spine (finish once; every vertical stands on it)

The gaps demand ONE Commerce domain and ONE Places substrate; the horizon fence
forbids a billing stack per engine. Build these first.

1.1 Commerce (closes gaps.yml commerce_shared_domain; consumed by marketplace
    coupons/boosts/analytics, dating premium, playlist donations, takeaway pro,
    creator monetization, local ads, referral benefits). New owners under the
    shared domain (justify in TaskContract.new_paths; existing-first):

        module Commerce
          Ledger       # append-only: charge/refund/credit/payout/fee; idempotent
          Provider     # abstraction over Vipps + Dintero; never a second stack
          Campaign     # coupons/bundles/referral credit; rules as data
          Entitlement  # playlist_pro/dating_pro/takeaway_pro/boosts; usable benefits
          Credit       # seller/referral credit; expires honestly, shown plainly
          Payout       # seller/creator payout schedule; readable status
          Receipt      # one honest receipt: line items, mva, delivery, total, ref
          def self.checkout(order, provider:, return_to:)
            total  = order.total_incl_mva_and_delivery       # honest_money
            intent = Provider.create_intent(order, total, return_to: exact_allowlist(return_to))
            Ledger.record(:charge_pending, order, intent)    # idempotency key = order.id
            redirect intent.approval_url                     # hosted; no card data
          end
          def self.webhook(event)                            # behind Shared::OutboundHttp (pinned)
            return unless Provider.verify_signature(event)
            return if Ledger.seen?(event.id)                 # redelivery-safe (lock!+reload)
            Ledger.record(event.kind, event.order, event)
            Entitlement.grant_for(event.order)               # usable, not just recorded
            EventEmitter.emit("commerce.settled", event.order)
          end
        end

    Proof: payments_in_provider_staging seam; redelivery regression on SQLite +
    FOR UPDATE; receipt rendered comparison; honest_money predicate. Operator
    gates money. Fences: payment never buys trust/moderation/rank; no dark patterns.

1.2 Places substrate (closes maps_poi_substrate; maps surface done but unconsumed
    as a service). Public API consumed by every vertical:

        module Places
          def self.near(lat:, lng:, radius_km:, kind: nil)
            POI.within(radius_km, lat, lng).filter(kind).rank_by(distance, trust)
          end
          def self.claim_or_suggest(user, place)
            place.persist_or_queue_review; TrustScore.signal(:place_claim, place)
          end
        end

    Proof: >= 2 verticals consume Places in a rendered journey;
    maplibre_runtime_and_vendor_decision seam closed by operator (licensing)
    before tiles ship; person area never exact coordinate.

1.3 CityFeed (closes brgen_city_population_seeds [content; CitySeed covers 43
    registry cities but no column/reader], brgen_cold_start_feed; workstream
    brgen_feed_ranking_deterministic [picked]):

        module CityFeed
          def self.for(user, city)
            return following_union_city_popular(user, city) if user.follows.empty?
            deterministic_rank(scope: city.posts.visible_to(user),
              signals: [recency, local_relevance, trust, engagement],   # SQL union
              diversity: cap_per_author_and_tag,
              explain: "why_am_i_seeing_this" link per card)
          end
          def self.seed(city)
            CitySeed.read(city).each { |row| upsert_public_domain_row(row) }  # add reader
            # real local public sources, attributed; never fabricate people/posts
          end
        end

    Proof: cold-start journey renders a non-empty local attributed feed for a new
    guest in each registry city; first_screen + content_honesty. No neural ranker.

1.4 Trust (closes commerce_private_seller_verification; private seller has no
    organisation number, needs its own proof):

        module Trust
          def self.badge(subject)
            return :verified_org     if subject.organisation_number_verified?
            return :verified_private if subject.id_verified? && subject.phone_verified?
            return :new_member       # honest, not a stigma; shows how to verify
          end
          def self.report_path(surface)
            ModerationWorkflow.open(surface, reporter: current_user)  # one tap, plain
          end
        end

    Proof: badge unit + rendered trust panel; human_accessibility_participant_review
    for plain language. Payment never buys a badge; moderation never sells.

1.5 Attention (closes messenger_notify_suppression; calm by default):

        module Attention
          def self.notify(user, event)
            return if user.quiet_hours?(now)                # default 22:00-08:00, editable
            return if event.conversation_open_for?(user)    # suppress while reading
            return if over_budget?(user, event.kind)        # daily budget per kind
            deliver_later_as_digest(user, event)            # batch non-urgent
          end
        end

    Proof: suppression regression (open conversation => no push); digest rendering;
    messenger_journey_in_a_browser seam.

1.6 Onboarding (guest -> member, plain, Vipps-first; Vipps login mock exists):

        module Onboarding
          def self.first_run(visitor)
            show_value_first(visitor.city)                  # guest sees value, no wall
            offer_one_step_signup(method: :vipps)           # oauth_callbacks_live seam
            ask_only: [display_name, city]
            explain_plain_nb("Vi bruker Vipps for å logge inn. Ingen passord å huske.")
            consent_plainly(privacy, terms)                 # sharing default closed
          end
        end

    Proof: guest-first journey; oauth_callbacks_live seam; accessibility; plain-
    language review.

### Phase 2 — Marketplace (markedsplass) -> bol.com parity

Engine: RAILS/brgen/engines/marketplace. README: shop-first today; individual-
listing model exists but classifieds experience unfinished. DONE: category + FTS
search, locality filters, facets, saved searches, wishlist, reviews, public
listing questions, variants, order state, returns, native seller surface,
duplicate detection (Listing#duplicate_of, satisfied). Planned (apps.yml): Solidus
core mount, starter storefront, native marketplace features, Dintero split
checkout, Amazon feature parity map, AI recommendations.

2.1 Finish the classifieds flow (the unfinished individual-listing experience):
    60-second photo-first listing, suggested honest price range from similar,
    auto category + place via Places, plain safety tip, duplicate check on publish.
2.2 Canonical product catalog keyed by GTIN/EAN — one product page, many offers
    (local shops + private sellers) — the bol mechanic, reachable on SQLite.
2.3 Professional partner-seller program with Trust.badge verification.
2.4 Deterministic recommendations + "often bought together" from co-order counts
    in SQL (closes marketplace_ai_recs; no neural ranker). Explain "Fordi du så på ...".
2.5 Coupons/referral credit/bundles via Commerce::Campaign (closes marketplace_coupons).
2.6 Seller analytics: plain counts (views/contacts/sold), liquidity restock
    suggestions (closes marketplace_seller_analytics; marketplace_liquidity
    knowledge gap — liquidity before ads).
2.7 Paid boosts via Commerce, labelled "Sponset", organic rank stays quality-
    weighted (closes marketplace_paid_boosts; payment never buys rank/trust).
2.8 Contact relay (marketplace_contact_relay) stays BLOCKED until inbound mail
    routing + per-listing addresses on vm23 exist; else in-app message only.
2.9 Land a bol.com parity map beside the planned Amazon parity map.
    WALLED: bol catalog scale, ML, national logistics. NATIVE: a CITY product
    catalog, Places geo-locates stock, Commerce split checkout (Dintero) + returns.
    Proof: empty->seeded journey, 60s listing on a phone, checkout staging seam,
    sponsored label rendered, first_screen.

### Phase 3 — Takeaway -> DoorDash/foodora parity

Engine: RAILS/brgen/engines/marketplace/engines/takeaway; canonical route /food on
the Marketplace host (takeaway.<city> compatibility mount). DONE: discovery +
cuisine filter + live search + nearby, menus/availability/photos/hours/min-order/
fees/radii, guest ordering, server-calculated totals (client never trusted),
guarded lifecycle, delivery-area validation (Restaurant#within_delivery,
satisfied), cart expiry (Order CART_TTL + expire_stale_pending!, satisfied), tip.

3.1 Live tracking map + driver assignment + honest ETA (prep time + distance, not
    a sold guess). 3.2 Driver surface. 3.3 Scheduled + group orders. 3.4 Subscription
    free-delivery tier via Commerce::Entitlement (DashPass-style). 3.5 Restaurant
    coupons/loyalty/promotions via Commerce::Campaign (closes takeaway_pro_surface).
    3.6 Reorder/favorites; ratings + photo reviews.
    WALLED: the Dasher/rider logistics network, dispatch ML, capital, insurance.
    NATIVE: restaurant self-delivery + local courier coordination on the spine.
    Proof: hungry-user journey end to end, cart-expiry honesty (real TTL, not fake
    urgency), checkout staging seam, live tracking journey, pro coupon rendered.
    Never fake a live ETA or status badge.

### Phase 4 — Dating -> happn/Tinder/Badoo parity

Engine: RAILS/brgen/engines/dating. DONE: home#next one-candidate deck, like/
dislike, rewind, matches page, who-liked-you page, five stored daily picks,
mutual Profile.oriented_for (dating_two_sided_ranked_for satisfied), Vipps-verified
phone, human-reviewed random-pose selfie verification, three profile prompts,
path_crossings + nearby surfaces (route screenshots).

4.1 Surface path_crossings as a first-class "people you crossed today" feed —
    happn's whole product, data already exists. 4.2 Badoo-style people-nearby grid
    + interests discovery (area-only, never exact). 4.3 Premium tier (closes
    dating_premium_boost) unlocking unlimited rewind / who-liked-you / passport;
    super-like; boost — via Commerce::Entitlement, member-visible real benefits,
    price incl mva, no dark pattern, no fake scarcity. 4.4 Icebreaker games; safety
    center. 4.5 Safety defaults: private by default, plain "Du bestemmer hvem som
    ser deg. Del aldri adresse.", block/report one tap, verification optional.
    WALLED: WebRTC video/voice (STUN/TURN host infra, blocked); liquidity at scale.
    NATIVE: verified-local cross-paths with Vipps-verified phones — happn done
    honestly. Premium never buys consent/trust/moderation; deterministic ranking.
    Proof: safety-default journey, mutual-match journey, premium benefits rendered
    + staging, human review of safety copy. Liquidity stays an honest market fact.

### Phase 5 — Messenger

DONE: core DM (conversation_between, mark_as_read), reactions. 5.1 Suppression
while open (spine 1.5). 5.2 Business inbox + CRM via Commerce::Campaign (closes
messenger_business_crm; orders + messages joined; plain labels new_order/question/
refund). 5.3 WebRTC voice/video (messenger_webrtc_calls) stays BLOCKED until
STUN/TURN host infra; ship honest_unavailable("Taler støttes ikke ennå.") meanwhile.
    Proof: suppression regression, conversation journey seam, business inbox
    journey; calls INCONCLUSIVE until host infra proven.

### Phase 6 — Maps substrate

Surface done; make it the service (spine 1.2). Consumer journeys: marketplace
listings_near -> Places.near(kind: :for_sale); takeaway restaurants ->
:restaurant; dating nearby -> :person_area (area only); brgen events -> :venue;
commerce local_ads -> geo_target (after liquidity). Tiles gated on
maplibre_runtime_and_vendor_decision (licensing) operator seam. Proof: >= 2
verticals consume Places in a rendered journey; person area never exact.

### Phase 7 — Playlist/Radio -> SoundCloud/whyp.it parity

Engine: RAILS/brgen/engines/radio/playlist; host radio.<city> (playlist.<city> no
longer resolves). DONE: playlists/sets, collaborators owner/editor/viewer, URL
import (YouTube/Spotify/SoundCloud/Whyp/direct), hosted uploads for real accounts,
synced listening parties + chat, moment-pinned comments (SoundCloud's signature),
likes/listens discovery, DillaSketch -> DillaRenderJob -> Shared::DillaProcessor ->
publish as track.

7.1 Waveform render + scrub UI (the visual signature; media pipeline exists,
    moment comments exist). 7.2 Creator profiles + follow + activity feed; reposts;
    creator stats. 7.3 Donations + ad-free tier via Commerce (closes
    playlist_creator_donations); referral benefits usable (closes
    referral_reward_consumption — define + wire the gate, not just record).
    7.4 Lossless/hi-fi playback path for OWNED uploads (the whyp angle).
    7.5 Offline listening (PWA).
    WALLED: major-label catalog licensing; SoundCloud scale/royalties. Stream only
    licensed/owned audio (show_rights_honestly). NATIVE: local curation + listening
    rooms + creator ownership + dilla generation — SoundCloud does not do this.
    Proof: donation staging seam, ad-free entitlement gate regression, rights
    honesty check, radio_tunnel_rendered_review + radio_whyp_tracks_imported seams.

### Phase 8 — TV

Engine: RAILS/brgen/engines/radio/tv; host tv.<city>. DONE: VOD structure;
Tv::Broadcast models the live state machine. 8.1 Local VOD + creators first screen.
8.2 Live streaming (tv_live_stream_infra) stays BLOCKED until a media server
(MediaMTX/SRS/nginx-rtmp) + delivery tier on the host; Broadcast.transition +
deliver_via_cdn_tier + calm follower notify when ready. Never ship a fake "Direkte"
badge. Proof: VOD journey; live INCONCLUSIVE until host media tier proven.

### Phase 9 — brgen core

DONE: auth, communities, posts (hot/fresh/top), threaded comments, votes/likes,
hashtags, mentions, follows, notifications, DM, FTS5 search, recent searches
(satisfied), reading time, city subdomain routing (DomainRegistry), proximity,
moderation (ModerationWorkflow/TrustScore), media pipeline (blurhash +
responsive_image_tag), identity/trust primitives, Activity graph (EventEmitter),
shared concerns (Notifiable/ActivityTrackable/GeoLocatable/Votable/Commentable/
Taggable), LinkEmbed (oEmbed behind Shared::OutboundHttp).

9.1 Recurring events/ticketing beyond an external link (closes brgen_recurring_events)
    via Places venues; opt-in calm reminders. 9.2 Creator monetization (closes
    brgen_creator_monetization) via Commerce creator fund. 9.3 Minimal art-directed
    sponsored banner (brgen_art_ad_banner) ONLY when a certified consent platform +
    approved copy + image rights exist; AdSense stays gated; else no ad slot.
    9.4 ActivityPub inbound (brgen_activitypub_inbound) stays BLOCKED until remote
    media proxying + remote moderation + blocklist exist; do not ship half-federation.
    Proof: home first_screen, events journey, sponsored gate unit, creator tip
    staging seam.

### Phase 10 — Visual / CSS micro-pixel program

Design constitution: tokens.yml (visual_identity signal_and_stillness, scale,
layout_rules, typography, worn_type, pixel_perfection, rams_checklist, ui_polish,
ultraminimalism, ux_laws, vertical_accents, vertical_accent_ink). css_architecture.yml:
cascade layers reset/tokens/base/components/utilities/autofix; !important forbidden
in components/utilities/autofix; specificity ceiling 0,3,0 in WARN mode. Instruments:
geometry_probe walk.js/design_laws.js, rendered_geometry placement/space/grammar/
composition/token checks, type_laws, contrast, reflow, occlusion, viewport_spill,
layout_snapshot drift, first_screen, kanso_surface, web_vitals_budget.

10.1 Drive the measured off-scale baselines (tokens.yml#tokens.scale.baselines) to
     zero per surface, before/after screenshots at 390/768/1280 under RAILS/*.png:

        apps:  off_scale_radius 19, tracking 6, opacity 20, duration 14, off_token_color 21
        face:  tracking 12, opacity 27, duration 26, off_token_color 8 (fix part files,
               never face.runtime.js)
        compiled.amber:    font-size 40, padding 68, margin 35, gap 40, color 37,
                           radius 17, letter-spacing 13, line-height 15, weight 9,
                           z-index 13, box-shadow 1
        compiled.brgen:    font-size 64, padding 127, margin 56, gap 48, color 67,
                           border-color 26, radius 27, letter-spacing 17, line-height 18,
                           weight 10, z-index 44, box-shadow 1
        compiled.bsdports: font-size 27, padding 49, color 20, radius 12, z-index 10,
                           box-shadow 1
        compiled.mrdamascy: padding 30, margin 25, color 12, z-index 8, box-shadow 0

     The box-shadow 1 in amber/brgen/bsdports is a flat_ui candidate: strip it or
     record the named exception pixel_perfection.exception_policy demands.
10.2 Add a z-index scale to tokens.scale (compiled z-index counts have no token
     owner: brgen 44, amber 13, bsdports 10, mrdamascy 8). Name the layer stack in
     CSS, not magic integers.
10.3 Move specificity ceiling 0,3,0 from warn to error after cleanup.
10.4 Enforce typography.accessibility: body_min_px 16, mobile_input_min_px 16,
     normal_text_contrast 7.0, large_text_contrast 4.5; line_length 45-75ch ideal
     66; line_height allowed [1,1.25,1.4,1.5,1.6] body 1.5; max 2 families / 3
     weights / 8 sizes; h1_body ratio 1.75-5.5; all_caps tracking 0.05-0.15em;
     body oldstyle-nums, tables tabular-nums; orphans/widows 3.
10.5 Enforce layout_rules: 8px rhythm + 4px hairline; 12-column grid; proportional
     split 0.618/0.382; gap before margin; internal padding <= external separation;
     body left-aligned right rag; centre text <= 3 lines; 44/48px touch in bottom-
     centre thumb zone; F/Z scan path.
10.6 ui_polish: one button family (button-primary/ghost/danger/small/link/block/
     share); finish RAILS/refinements.yml shared-010 (retire .button-small for
     $compact-contexts in RAILS/__shared/app/assets/stylesheets/_buttons.scss);
     space_not_lines cards (gap + elevated surface, not hairline borders); chrome
     i18n nb/en via t() (ratchets chrome_i18n_lint.rb, empty_state_lint.rb,
     adhoc_empty_lint.rb); every empty state has an action.
10.7 Native modernisation (no third renderer, no ornament): cascade layers across
     engine sheets; logical properties; clamp() typography within scale; container
     queries for dialect cards; :has() for presentational state; text-wrap balance/
     pretty + Norwegian hyphens lang=nb; :focus-visible rings from tokens;
     font-display swap + variable sans (no serif); content-visibility for long
     feeds; scrollbar-gutter stable; accent-color + native dialog/popover where
     Stimulus wraps them; Turbo view transitions only as measured progressive
     enhancement with reduced-motion equivalent.
10.8 Reorganise stylesheets by engine ownership under the layer stack; run
     dead_css_sweep/dead_css_static/dead_css_coverage; collapse CSS_DUPLICATE_DECLARATION
     (6) + CSS_SHORTHAND_COLLAPSE (22); prove css_minify_integrity + css_brace_balance;
     critical first-screen CSS via tools/rails/build_all_css.rb under first_screen +
     page_weight budgets.
10.9 Motion grammar: stillness default; animate existing elements before new;
     bound population/duration/amplitude/cost/lifecycle; every meaningful animation
     has a reduced-motion equivalent. Void grammar: negative space structural; one
     focal point + one primary action per first screen. Rams checklist on every UI diff.
     Work TYPOGRAPHIC_GRID (1711) + VERTICAL_BREATH (2289) to zero per surface;
     operator gates every rendered value.

### Phase 11 — DRY / KISS

DRY and KISS are law roots; dup_census.yml tracks 161 sets with ceilings; the
proposals ledger refuted several consolidation moves (family moves, lazy-class
extraction, best-of-N, parallel streams). DRY = measured duplication with a named
consumer, not ideological dedup. KISS = one owner per concept, not fewer files.
The spine ratchet + cohesion census forbid convenience splits.

11.1 Triage dup_census intentional vs accidental. Intentional: screenshot baselines
     for generic routes (/up, historical locations) shared across apps; amber logo
     plates/asset copies; mrdamascy standalone Vipps wordmark; BIZ published pairs.
     Accidental candidates: MASTER/lib/operator/domain_signals.rb vs
     OPENBSD/lib/domain_signals.rb (verify OPENBSD self-containment on the box
     justifies the copy before merging); shared vs brgen anonymous_post_quotas
     migration copy (engine-promotion residue); four identical Rakefiles
     (MASTER/web, amber, bsdports, mrdamascy).
11.2 Finish redundant_core_require_cleanup (85; convergence partial); spine test
     green, body ceiling ratchets down.
11.3 DENSITY_identical_branches + DEAD_CODE (6) by file with focused test.
11.4 dead_route_sweep + content_dedup_scan; retire what has no consumer; price each
     retirement in sunset.yml with its measured catch.
11.5 KISS targets, measure before splitting: pass_runner/assessment_matrix.rb 74 KB,
     command_registry help 40 KB / host 60 KB / review 58 KB, CONFIGURATION_SHAPE 87,
     CHOICE_OVERLOAD 4, BOOLEAN_TRAP 2. The 812 SMALL_FUNCTIONS / 650 FEW_ARGUMENTS /
     447 CYCLOMATIC / 392 ABC findings are a baseline; route only what a caller or
     reading proves painful. Keep one counting method (CodeMetrics.body_lines shared
     by lint:spine and SmallFunctionsRule).
11.6 Resist new abstractions: the refused list is the KISS backbone. Every
     extraction names the caller that needs it.

### Phase 12 — Security

12.1 ROTATE the GitHub PAT the operator pasted into chat. It was used only for the
     clone and contents-API commits; it appears in no repo file/log/paste/receipt.
     Add rotation to operator_seams.yml.
12.2 Run security_sweep + RAILS/test/tracked_secrets_test.rb on a compatible host;
     confirm filter_parameter_logging covers password/phone/authorization/api_key/
     access_token/refresh_token/private_key/credit_card/card_number/iban.
12.3 SsrfGuard: all-answer fail-closed, pinned ipaddr, SNI hostname, no env proxy,
     bounded phases; every new HTTP client rides it (ROBUSTNESS_outbound_fetch_is_pinned).
     Redirects checked before following (WebBrowse Location; ExternalAudit same-host).
12.4 CSP report-only until PUB5_CSP_ENFORCE=1; csp_enforced_on_vm23 seam operator-owned;
     propose the enforcement rehearsal with report review.
12.5 Host egress (outbound_http_host_egress seam): network-layer denial of private/
     metadata routes; application pinning is not a substitute; propose the pf rule
     set as a deploy-host change with native proof.
12.6 Confirm rate limits pinned (WriteThrottle 60/min, password 8/3min, reset 5/3min,
     account security 6/10min); session cookie flags + multi-domain contract; Vipps
     params[:to] exact "checkout" allowlist (no open redirect).
12.7 PersonalPermissions default-deny; financial read-only; no adapter ships without
     it. Repo is public: no receipt/paste/screenshot carries a secret/private path/
     personal datum.

## 5. External acceptance gates — not global implementation blockers

These entries are **narrow acceptance gates**, not reasons to stop unrelated
repository work. For each one, continue local implementation, contracts,
fixtures, dry-runs and failure-path tests that do not need the missing external
resource. Only the corresponding live-production claim remains INCONCLUSIVE
until its evidence exists. Do not convert a mock, local browser, estimate or
configuration file into live acceptance.

- **Messenger WebRTC calls** — local signaling, call-session lifecycle,
  permission UX, teardown and same-LAN/ICE tests can proceed using the existing
  ActionCable path. Reliable cross-NAT media and production acceptance still
  require host STUN/TURN and real network-path proof.
- **Marketplace contact relay** — privacy-preserving in-app contact can proceed
  through the existing buyer/seller conversation, including masking and a
  reviewed reveal flow. Per-listing inbound email aliases and forwarding remain
  gated on vm23 MX/relay routing.
- **TV live streaming** — provider-neutral ingest/delivery contracts, local
  loopback adapter, readiness checks, failure states and runbook work can
  proceed. Production ingest, transcoding and viewer delivery require the
  selected media server and host delivery tier.
- **ActivityPub inbound** — local protocol parsing, actor identity, moderation,
  blocklist semantics, bounded inbox processing and fixtures can proceed.
  Federation must not be enabled until remote media proxying, remote
  moderation and the blocklist are operational and tested.
- **Map tiles** — the MapLibre surface, provider interface, attribution,
  fallback and local fixture rendering can be tested without choosing a
  production tile contract. Production tile delivery remains gated on the
  vendor/licensing decision, attribution and usage terms.
- **Payments live** — provider-neutral contracts, signed-webhook fixtures,
  duplicate/out-of-order delivery, integer minor units, idempotency, refunds and
  failure paths can be tested locally. Real charge/refund acceptance requires
  Vipps/Dintero provider staging; never use a live customer charge as a test.
- **PWA on real devices** — manifest, service-worker upgrade/rollback, stale
  cache, offline shell and upload behavior can be tested in the local browser
  harness and device emulation. Native install, platform prompts, offline
  recovery and media upload still require real Android and iOS devices.
- **SEO** — canonical URLs, metadata, robots, sitemap and structured data can
  be source- and route-tested now. Public crawl/indexing acceptance requires
  registered canonical hosts, DNS/TLS and a real crawler/browser pass.
- **Accessibility** — semantic markup, automated checks, keyboard operation,
  focus behavior, contrast and reduced-motion tests can proceed immediately.
  Human participant review remains required for the final accessibility
  acceptance claim; automation is not a substitute.
- **Live journeys** — local browser journeys and per-app contract tests can
  proceed against local fixtures and test accounts. Production tenant isolation,
  OAuth callback, messenger streaming and first-screen claims require the
  named live hosts and browser evidence.
- **OAuth callbacks** — local callback handling, state/nonce/PKCE validation,
  failure paths and provider fakes can be tested now. Real callback acceptance
  requires provider registrations, exact public redirect URIs and credentials
  in the approved secret store.
- **Radio** — player/tunnel states, import parser, metadata validation and
  empty/error states can be exercised with fixtures. Rendered radio review
  still requires a real browser; Whyp track import requires a verified source,
  provider access and rights/attribution evidence.
- **Ops alerts** — event classification, redaction, retry limits and delivery
  adapter contracts can be tested against a local fake receiver. Live paging
  remains gated on an operator-owned allowlisted relay endpoint and a secret
  outside the repository; never replace this with a Slack webhook.
- **DNSSEC** — zone generation, DS calculation, consistency checks and
  preflight can be tested locally. Publishing DS records and proving public
  resolution remains a registrar-owned action.
- **Backup and recovery** — local backup manifests, integrity checks and
  restore drills can be improved now. The second off-host copy, recovery of
  DNSSEC/DKIM/SSH/ACME keys and a tested off-host restore require the external
  host, key custody and operator console.
- **CSP and outbound egress** — inventory current origins, generate report-only
  policies, add local response-header tests and exercise the outbound-host
  guard now. Enforcing CSP/egress on vm23 remains gated on review of actual
  production asset/API origins and a watched host change with rollback.

The operator-seam registry now states this scope rule explicitly: an unmet
seam blocks only the live claim that requires it. It never blocks independent
source changes, local/contract tests, dry-runs, adapters or failure-path proof.
Keep production readiness INCONCLUSIVE until the exact evidence is recorded.

## 6. Acceptance — the love contract (every public surface must pass)

    module LoveContract
      def self.accepts?(surface)
        one_job(surface)                   # one focal point + one primary action
          .and plain_language(surface)     # nb copy, plain, no jargon
          .and guest_first(surface)        # value before signup
          .and fast_first_paint(surface)   # first_screen + web_vitals on a low-end phone
          .and thumb_reachable(surface)    # primary action bottom-centre; >= 44/48px
          .and honest_empty(surface)       # empty state teaches + offers next action
          .and visible_trust(surface)      # who, verified how, why safe
          .and safe_by_default(surface)    # privacy closed; consent plain; report one tap
          .and calm_notifications(surface) # budget; suppress while open; quiet hours
          .and offline_tolerant(surface)   # PWA shell + cached read + honest offline
          .and accessible(surface)         # keyboard_flow + axe + reduced motion
          .and recoverable(surface)        # every error says what happened + next step
          .and honest_money(surface)       # total incl mva + delivery up front; sponsored labelled
      end
    end

Proof gates: local focused tests + changed-line Law assessment; rendered screenshots
390/768/1280 under RAILS/*.png (run-scoped, never reused, before/after); keyboard_walk,
accessibility_axe, journey_invariant, reflow, occlusion, contrast, design_laws; then
the named live seam. Status vocabulary: RUN / NOT_RUN / INCONCLUSIVE — never a false
PASS. A stopped run is resumable, never successful. Aesthetic taste and rendered
values stay operator-owned; the checks measure objective invariants, not beauty.

## 7. Routing and registry intake (no new backlog)

Route each slice to its owner, with the measurement that justifies it:
- concrete defect claim -> MASTER/data/proposals.yml (state open; refutations recorded
  with the measurement, never deleted)
- missing capability -> MASTER/data/gaps.yml (respect satisfied/blocked statuses)
- human-only evidence -> MASTER/data/operator_seams.yml (needs/evidence)
- implementation state -> MASTER/convergence.yml (a named next measurement, not a
  status bump)
- polish candidates -> MASTER/data/ideations/polish.yml (with critique; mechanical
  rows regenerable by Operator::PolishLens; taste operator-owned)
- product features -> RAILS/apps.yml (feature truth) / RAILS/apps.horizon.yml (agent-ignore)
- UX refinements -> MASTER/data/law/ux_refinements.yml (90 MASTER UX rows, acceptance_required)
  and RAILS/refinements.yml (product; shared-010 open)
bin/master status --agent is the read-only union; there is no parallel Markdown
checklist. This handoff is session evidence, not a registry.

## 8. Definition of done — "finished properly and loved"

A vertical is done when: its named gaps.yml rows are closed or honestly blocked;
its apps.yml planned features landed with rendered acceptance; its parity-map
missing rows built on the shared Commerce/Places spine (never a per-engine stack);
its walls held honest (catalog scale/ML for bol, label licensing for SoundCloud,
liquidity for dating, driver logistics for DoorDash/foodora); the love contract
passes on a fresh sweep at 390/768/1280; the live seams closed by the operator;
and the truthful status is recorded. The strategy the architecture encodes: win
the city, not the category — one network across verticals, local before global,
useful over noisy. Each vertical competes on locality and trust joined to the
network, not on out-featuring a global incumbent from a 1 GB SQLite box. Dominance
copy without evidence violates persuasion_honesty/content_honesty; the BIZ plans
may argue the thesis, the product must show the proof.

## 9. Proof status of the intake session

RUN: git clone/log/ls-files/rev-parse; text reads; PyYAML parses (0 failures);
JSON parses; regex censuses; agent-contract byte comparison; FACE_WORLD segment
offsets; shebang/mode census; whitespace/newline census; .py census; layout_snapshot
geometry measurement; route_screenshots PNG pixel analysis (PIL/numpy); current-token
contrast computation; GitHub contents-API commits + ref verification.
NOT_RUN: every Ruby suite, rake task, Law detector, /fix lane, browser check, doctor,
boot smoke, hook, deploy, fresh visual sweep. Blocker: no Ruby >= 3.2 (Debian buster,
archived apt), no Chrome, no provider keys, no OpenBSD host; the sandbox recycled
and lost the local checkout; agent browser verification is refused by the constitution.
No Law PASS, no test PASS, no deploy claim, no design PASS. Re-measure everything.


## 10. Phase 13 — STUDIO owner/source reconciliation — 2026-11-22

Status: source reconciliation completed against the live owners and focused test
surfaces; targeted changes were pushed to `main`. This is an evidence update,
not a new backlog or a claim that the STUDIO suite passed.

The live tree has exactly four STUDIO owners: `dilla/`, `lora/`,
`postpro/` and `replicate/`. There is no `STUDIO/README.md` or
`STUDIO/lora/README.md`; the shared contract is
`STUDIO/replicate/README.md`, with local Dilla, Postpro and subject-specific
documentation. Do not create replacement owner READMEs merely to match the
proposal's assumed paths.

### Delivered source corrections

- **S-02 — Postpro prior-take retention slice: PARTIAL, proof NOT_RUN.**
  The live `Postpro::Constitution.retire_previous_renders!` path deleted prior
  media and JSON sidecars for the same source before drawing a new family. The
  method and its call were removed. Existing `available_output_path` continues
  to select timestamped siblings for generated batch names. Explicit one-shot
  grades now refuse an occupied media or sidecar destination; `--compare`
  also refuses an occupied comparison file; explicit stock-sheet destinations
  refuse collisions. The Postpro README now states append-only retention.
  Static regressions cover the absence of the retirement call and the occupied
  destination guard. No earlier media, source photograph or sidecar was
  deleted by this change.
  Files: `STUDIO/postpro/constitution.rb`,
  `STUDIO/postpro/lib/cli.rb`,
  `STUDIO/postpro/README.md`,
  `STUDIO/replicate/test/postpro_cli_contract_test.rb`.
  This closes the destructive Postpro path only. It does not yet provide
  the proposed cross-STUDIO `rake studio:takes SUBJECT` inventory or a
  unified take allocator through `output_paths.rb`; those remain open. Dilla
  already refuses collisions by default and exposes `--overwrite` as an
  explicit operator action, not as an autonomous default.
  Commits: `d5b9354ab701434976101da01e7bc739d68d61d7`,
  `ef30626cc2f3d68870e931797e4d128bcd281365`,
  `82a0fbee2f538c5c48b8091d19a0ac8c812119eb`,
  `1b4df126806ebdd9a3341b04a0a9a6c4c2bc2c48`.

- **S-05 — Doctor provider-key honesty: IMPLEMENTED, proof NOT_RUN.**
  `studio doctor` now reports `INCONCLUSIVE` when no usable Replicate
  credential exists, `FAIL` when a configured credential file is unsafe, and
  `PASS` only when a private credential is available. The report never prints
  the credential. Regressions cover a missing key and a world-readable token
  file. This gate is read-only and does not make a provider call.
  Files: `STUDIO/replicate/doctor.rb`,
  `STUDIO/replicate/test/doctor_test.rb`.
  Commits: `564002e085ea4a241a2b4eed4888a5d4f15e584b`,
  `dddb0c282cd1ed0a9dd94af0882619549d436d02`.

- **R-03 — Download boundary regression: IMPLEMENTED, proof NOT_RUN.**
  Added focused cases for public global-unicast IPv6-only DNS, private IPv6,
  mixed public/private DNS answers, HTTP 302 to a private address (not followed),
  and an interrupted/over-limit stream that must not publish a partial file.
  Existing client code validates the full DNS answer set, pins the connection,
  bounds transfer size and time, rejects redirects, writes to a same-directory
  temporary file and atomically renames only after success. This change adds
  tests; it does not add redirect-following behavior.
  File: `STUDIO/replicate/test/replicate_client_test.rb`.
  Commits: `cd3a4ed30084673f952c34bcae9ed0f4f3fa1372`,
  `281783d7d1154603aef04f0fc331e37f2a8d6e2d`.

### Proposal register reconciliation

- **S-01:** Dilla, Postpro and LoRA already emit different, owner-specific
  provenance/sidecar or training-manifest records. They include seeds and
  hashes where applicable. No universal manifest was added: a parallel schema
  would duplicate existing owners and would not by itself prove every output
  has a manifest. Cross-tool identity/chain correlation remains open.
- **S-02:** Landed as described above. The append-only regression and runtime
  suite remain NOT_RUN.
- **S-03:** No blind A/B player or preference ledger was added. Dilla already
  separates technical audit from listening acceptance. Musical acceptance
  remains an operator decision; no automated advance threshold is introduced.
- **S-04:** Replicate remains the only STUDIO provider. No second registry or
  speculative adapter framework was created. The subject-specific Merethe
  recovery fetch uses a fixed `raw.githubusercontent.com` URL at an immutable
  historical commit, accepts only an HTTP success, does not follow redirects,
  and verifies each response against the expected Git blob digest. It still
  uses `Net::HTTP.start` without explicit socket IP pinning or proxy
  suppression; keep that exact recovery path under review before extending
  outbound fetching. No broad source scanner was added while this known,
  narrowly scoped fetch remains outside the pinned Replicate client.
- **S-05:** Landed as described above. Full Doctor report and tests NOT_RUN.
- **R-01:** Replicate's video path estimates and reserves spend before the
  prediction request. There is no general cost receipt for every paid model
  call; reliable per-call actual pricing data is not yet established. No
  estimated amount is represented as an actual charge.
- **R-02:** Existing video per-call and per-run caps are enforced before the
  prediction. A generic per-session/per-day cap and explicit spend-approval
  workflow for every paid path remain open.
- **R-03:** Added the DNS/IPv6/redirect/interrupted-transfer regressions above.
  Redirects are refused, not traversed. Test execution NOT_RUN.
- **R-04:** Existing download code preserves an old output until successful
  atomic rename, refuses symlink destinations, and bounds bytes/time. Added an
  interrupted-download fixture. A separate owner-only output-directory mode
  assertion is not established by this change and remains open.
- **R-05:** No adapter contract was added for a hypothetical second provider.
  One provider does not justify a second registry or an unused abstraction.
- **D-01:** The active corpus is `STUDIO/dilla/data/music_theory.json`, not
  the proposed `music_theory_chords.yml`. No duplicate corpus or synthetic
  entries were created. A source/citation audit of each corpus item remains
  open.
- **D-02:** Voicing and sound curation remain ear-led and operator-owned.
  No numeric acceptance threshold or agent-selected default was added.
- **D-03:** Seed and renderer/provenance records already support deterministic
  rerendering at the source/parameter level. An alignment-based
  `dilla:reproduce` task is not implemented or proved.
- **D-04:** The proposed sketch-to-render-to-playlist publication receipt and
  end-to-end journey were not found in the inspected proof surface. Open.
- **D-05:** No new measurement/dashboard was added without a named reader and
  selection consumer. Open.
- **D-06:** No new CPU/concurrency budget or 1 GB load fixture was added.
  Existing bounds are not evidence of this proposed workload guarantee. Open.
- **P-01:** Postpro's existing grade sidecars record input/output digests,
  recipe/parameters, seed and grade-code digest. A stable prior-take identifier
  shared across all output types is not established. Open.
- **P-02:** Existing `--compare` and random-family contact sheets provide
  rendered side-by-side material. They do not automatically grant visual
  acceptance; operator comparison remains required.
- **P-03:** Looks and presets remain existing product-owned configuration/code.
  No mutable agent-owned preset source or default was introduced.
- **P-04:** No first effect was selected without a measured before/after cost
  and operator-owned visual purpose. Open.
- **L-01/L-02:** Existing `Studio::Lora::Consent` gates actions separately:
  generation, training, publication and distribution require explicit
  subject permissions and matching source-rights evidence. Source files,
  directories and consent/evidence records are checked for private ownership,
  link count and mode. The validator checks private training manifests.
  No duplicate consent schema or parallel permission authority was added.
- **L-03:** No training estimate/receipt/approval/spend workflow was invoked or
  added. Paid training remains operator-gated; the generic cost receipt is open.
- **L-04:** Existing validators and Doctor inspect subject-private paths and
  local Git history. The new world-readable fixture covers Replicate token
  files, not a full weights/media permission census; do not overstate it.
- **L-05:** Candidate contact sheets/reports are already private; exact
  likeness-version approval remains a human review recorded in the subject's
  local configuration. No agent acceptance was created.
- **L-06:** The full consent-to-publication journey was not run. No real
  subject's private data was opened, trained, rendered or published in this
  session.
- **L-07:** Revocation propagation to public surfaces was not verified or
  implemented. Open.

## 11. Phase 14 — BIZ owner/source reconciliation — 2026-11-22

Status: one index-inventory guard was landed; rendered comparison, legal
research verification and the complete BIZ build/print chain remain NOT_RUN.

- **B-01:** `bp_print.mjs` already checks PDF page count and page dimensions,
  rasterizes every page for visual inspection, and writes a first-page image.
  Rasterization is not a baseline comparison or human acceptance. No rendered
  before/after equivalence or approved redesign diff was fabricated. Gate open.
- **B-02:** No Ruby port was made. The current build chain is several
  interdependent JavaScript modules; replacing them without a local executable
  baseline and per-tool rendered PDF evidence would risk changing argv and
  published-pair semantics. Any port must remain a deliberate, one-tool,
  one-commit migration with exact CLI parity and format-aware proof.
- **B-03:** `BIZ/README.md` documents editable masters in `BIZ/tools/` and
  the build/retemplate/check/print/index sequence. A source-newer-than-published
  staleness check plus regeneration receipt is not implemented. Do not infer
  freshness from the documentation.
- **B-04:** `bp_retemplate.mjs` carries the Bob2 token/print contract onto
  business-plan content, and Bob/Bob2/Bob3 templates remain preserved.
  A rendered equivalence report or operator-approved redesign record was not
  produced. Gate open.
- **B-05:** `BIZ/README.md` already defines a detailed evidence register,
  review states and separate qualified legal review. The high-risk
  `BIZ/research/husleieloven-2026.md` claim-by-claim audit was NOT_RUN; no
  legal claim or citation was changed. Software checks do not substitute for
  Norwegian legal-source verification or qualified review.
- **B-06 — INDEX COMPLETENESS: IMPLEMENTED, proof NOT_RUN.**
  `BIZ/tools/bp_index.mjs` now checks that every top-level workstream
  directory is represented by the active/archive index registry and checks
  that the retained `bob`, `bob2` and `bob3` templates each have both HTML
  and PDF files, with no unpaired or unexpected template basename. The BIZ
  README documents the gate. The regex was corrected after source read-back;
  no Node execution or regenerated index was run.
  Files: `BIZ/tools/bp_index.mjs`, `BIZ/README.md`.
  Commits: `47c010d6d9ec72ffd77f3d09787df3d5ef8272b1`,
  `e8cd913996f32a6f8aa6cbd99c6649ea720219a9`,
  `95e585da54d9c1c14a84a76446c77bcfb980bcfb`.
- **B-07:** The ten-workstream finish checklist is not implemented. A directory
  being indexed does not prove its source, generated pair, language,
  provenance, render or review is complete. Open.
- **B-08:** Tagged-PDF/reading-order/alt-text evidence was not generated.
  Chromium PDF output and rasterization alone do not prove accessibility.
  Open.
- **B-09:** The Studio/Replicate growth-revenue research source/date audit was
  NOT_RUN. No revenue claim or budget input was changed.

### Execution boundary for Phases 13–14

Remote source inspection and GitHub writes were available. There was no
working local `pub5` checkout in this execution environment; DNS resolution
for cloning was unavailable. Consequently the following are all **NOT_RUN**:
`ruby MASTER/tools/agent_context.rb --json --tree`, `cd STUDIO && rake check`,
`cd STUDIO && rake test`, Postpro focused tests, the complete Ruby syntax
census, every BIZ Node command, Chromium/PDF page renders, rendered visual
comparison, legal research audit and governed `/fix`. No source-level test
or README assertion is reported as a runtime pass. Re-run the mandatory
agent-context and focused owner suites from the live checkout before closing
these workstreams.


## 12. Phase 15 — STUDIO and BIZ completion sweep — 2026-11-22

Status: the remaining safe source-level changes in this sweep were committed
directly to `main`. No new owner, root file, Markdown backlog or parallel
registry was introduced. All new runtime/test proof remains NOT_RUN because
this environment has no working checkout and cannot resolve GitHub for clone.

### Delivered

- **L-07 / gallery revocation — IMPLEMENTED FOR THE LOCAL GALLERY, external
  propagation still OPEN.**
  `STUDIO/lora/selfies_gallery.rb` now rebuilds the local publication manifest
  from subjects whose action-scoped publication consent and per-source rights
  still validate. Missing/revoked permission excludes that subject, increments
  `excluded_subject_count`, and changes the manifest state to `PARTIAL`;
  other separately approved subjects remain listed. The manifest is written
  through a same-directory temporary file, fsync and rename, mode 0600; symlink
  and non-regular destinations are refused. Private source/render files are
  not deleted. Tests cover initial exclusion, a real synthetic
  permitted-then-revoked transition, owner-only manifest mode and symlink
  refusal. The consent-boundary test now expects a safe empty PARTIAL manifest
  rather than an exception before replacement. The STUDIO README explains
  that external copies/caches are not recalled.
  Files: `STUDIO/lora/selfies_gallery.rb`,
  `STUDIO/replicate/test/selfies_gallery_test.rb`,
  `STUDIO/replicate/test/consent_enforcement_test.rb`,
  `STUDIO/replicate/README.md`.
  Commits: `709df24c10c453ba6d3ac66084c39a3a22514e58`,
  `3905833f8af375b6d27335aa9b88b610fc419dea`,
  `5d5d58b68fcfb4a5565ec6496b5898a4b0ad4a58`,
  `bc129b4a235b0b09f246576f4a44975a61ec6b9d`.

- **R-01 / bounded video prediction receipt — IMPLEMENTED FOR THE FILM
  PATH; actual billing and other paid paths remain OPEN.**
  `Studio::ReplicateClient` now exposes `predict_with_receipt` while keeping
  the existing `predict` return contract unchanged. The receipt records
  model/version, prediction ID/status, metrics when returned and the catalogue
  estimate reserved before POST. `actual_cost_usd` remains null and
  `actual_cost_status` is `NOT_REPORTED_BY_PREDICTION_API`: this is not an
  invoice. `IdeaPicture#render_film` saves a private `.mp4.json` receipt
  beside each completed film, binding the source still and film by SHA-256 and
  recording duration, model, provider receipt and explicit
  `NOT_REVIEWED` visual/likeness states. Existing per-call and per-run caps
  still reserve before the paid prediction. Tests cover estimate versus
  actual-cost semantics, output hashes and private file modes.
  Files: `STUDIO/replicate/client.rb`,
  `STUDIO/lora/idea_picture.rb`,
  `STUDIO/replicate/test/replicate_client_test.rb`,
  `STUDIO/replicate/test/idea_picture_test.rb`,
  `STUDIO/replicate/README.md`.
  Commits: `4fbbbf5192b1121422e46647186fc9054a2f61cd`,
  `329ed26bd689064c58219aa85950a5b84d2e99b8`,
  `5a1f7c5e66360d1b7449ba8a3b381b83cec0a62f`,
  `cde63a127708aa1f22cd1f86a2fbf8c844796a38`,
  `c072346b9cc24a19769b1a5129537ae552895d80`,
  `b46f185b525d9cfbb90e0edb1e9d89db0e02bc1a`.

- **D-03 / future Dilla replay evidence — IMPROVED; replay command OPEN.**
  New `.provenance.json` files now record invocation mode/style, the Dilla
  renderer and `analog_core.rb` SHA-256 values, every `data/*.json` digest,
  and the operator-supplied sample loop's absolute path, byte length and
  SHA-256 when it is a regular non-symlink file. Missing/symlinked sample
  inputs are recorded as unavailable, not as reproducible. Tests cover the pinned
  fingerprints and unavailable source state. This does not create a replay
  command or certify that the complete runtime/environment can be reconstructed.
  Older provenance records remain incomplete. A full `dilla:reproduce` flow
  remains OPEN until every rendering input and external dependency has a
  verified recovery path.
  Files: `STUDIO/dilla/dilla.rb`,
  `STUDIO/replicate/test/dilla_test.rb`,
  `STUDIO/dilla/README.md`.
  Commits: `6681045a09cfb58ec327647b06f2f85c2405e49d`,
  `9b14243185cfaaa3a7f19186a614fdcc7d7b8aa2`,
  `b6fdf31e2b7fd28e6ecafa2efad05b1dc6a358e2`,
  `2e3b1f846c086ec0394213630be055b812f2c501`,
  `b5b43d2f6c02600b3bee69fcf611730f9761d8f1`,
  `66bbf3be261fb2955f279399a0cb591f9f1a06a5`.

- **S-02 / Postpro collision preservation — EXTENDED, proof NOT_RUN.**
  The explicit `--export-lut --output` branch now calls the same occupied
  destination guard as one-shot and stock-sheet output. Its focused static
  regression checks that the LUT path uses the guard. The earlier removal of
  the destructive prior-take retirement remains in force. A shared
  cross-STUDIO takes allocator/listing is not implemented: Postpro's source-
  adjacent outputs, Dilla's dated render lane and LoRA's subject-rooted media
  do not yet have one complete inventory boundary.
  Files: `STUDIO/postpro/lib/vocab_check.rb`,
  `STUDIO/replicate/test/postpro_cli_contract_test.rb`.
  Commits: `07db2286b6c09124670cfdd8eceb024be0b70866`,
  `7384deb9a35b95867978493abcbed7fb5f0686e1`.

- **B-01/B-03/B-06 / BIZ output integrity and freshness — IMPLEMENTED IN THE
  RELEASE CHAIN, proof NOT_RUN.**
  `bp_build.mjs` now refuses to work in an output directory containing any
  prior per-plan build directory, including a partial prior attempt. Use a
  fresh empty `BIZ_OUT_DIR`. `bp_print.mjs` refuses existing PDF, cover PNG,
  page PNG or print receipt destinations. After a successful print it writes
  a per-document `.print.json` record with SHA-256 for source HTML, PDF and
  cover PNG, byte sizes, page geometry/count, all-page raster count/bytes and
  explicit `NOT_REVIEWED` visual/accessibility states. The record is
  published atomically without replacing an existing receipt.
  `bp_index.mjs` requires matching print receipts for active plans and
  Ragnhild's funding guide; verifies their filenames, hashes, geometry, PDF/
  cover byte sizes and full-page raster count against the receipt; and checks
  editable HTML freshness separately from print/PDF
  freshness. Archives are still checked for their existing HTML/PDF pairs but
  are not forced through the new receipt gate. The BIZ README describes the
  scratch build, manual full-page/cover review and precise copy-in step.
  Files: `BIZ/tools/bp_build.mjs`, `BIZ/tools/bp_print.mjs`,
  `BIZ/tools/bp_index.mjs`, `BIZ/README.md`.
  Commits: `012abf6f91e90ba9c90b732d9a7e95d79144e5a1`,
  `5d49e682ee3325d1f5ef3fef357f64fac9d34866`,
  `93ca662cbb777d7a40aa6a16b3c25547ded0e961`,
  `ca812aa0eff07bdcf3350d9a6549f2df026186cc`,
  `f43ba6e7de5aded702d426a8795d029842026a09`,
  `90933990a936be2b21f4d87e16982085b15c9f26`,
  `58c77c5219a51b5d8fc5275919778184ed1adfdf`,
  `61821895eb2bf205cbd6cbc5340e2a3c039ae862`,
  `9b8b858b58459953f3e7db5b92371198d5d19923`,
  `d9cb370dee08b37163167a84297e5ce22df0fcf5`,
  `87ca9087f0c121bf7830b01754ad50ab7e676dc9`.

### Remaining operator/evidence boundaries

- No persistent per-day/all-provider spend ledger or generic pre-payment
  approval gate was added. Existing video estimates/caps cover the configured
  MiniMax path; other paid image, film and training calls do not yet share one
  persistent spend authority. The prediction API does not prove final billing.
- Local gallery rebuild does not retract files already distributed, copied or
  cached outside the local manifest. Repository visibility/history cleanup and
  subject-data retention are separate operator actions.
- No complete cross-STUDIO take inventory was added because the known output
  producers span different roots and, for Postpro, arbitrary source-adjacent
  directories. A partial listing would misrepresent completeness.
- Listening acceptance, likeness review, rendered visual acceptance, rights
  attestations, legal-source review, PDF accessibility review and publication
  approval remain human-owned. Print/film receipts deliberately say
  `NOT_REVIEWED`; no visual/audio/legal approval was inferred.
- BIZ active HTML/PDF/PNG/print-receipt pairs have not been regenerated or
  copied into the published directories. The new index gate will require the
  receipts after an operator-reviewed scratch release is copied in.

### Execution boundary for Phase 15

Remote GitHub source inspection and direct file commits were available. A fresh
local `git ls-remote https://github.com/anon987654321/pub5.git refs/heads/main`
again failed because this execution environment could not resolve
`github.com`. Therefore these remain **NOT_RUN**: mandatory
`ruby MASTER/tools/agent_context.rb --json --tree`; `cd STUDIO && rake check`;
`cd STUDIO && rake test`; focused Dilla, gallery, Replicate and Postpro tests;
Ruby syntax census; BIZ Node syntax/build/check/index commands; Chromium/PDF
generation; print-receipt/index validation against real published files;
rendered visual comparison; legal research audit; governed `/fix`; deployment.
No source read-back, authored regression or GitHub write is represented as a
runtime test pass. Re-run the mandatory context and owner suites from a
compatible local checkout before closing these lanes.


## 13. Phase 16 — STUDIO take identity, BIZ source graph, Core browser consent — 2026-11-22

Status: source changes are on main and were read back. One isolated Ruby
identity harness ran successfully. Project suites, browser execution, rendered
PDF review, legal-source review, governed /fix and deployment remain NOT_RUN.

### STUDIO — Postpro random-take identity

STUDIO/postpro/constitution.rb now derives a stable postpro.take.v1 SHA-256
identity from the input image digest, seed, take number, look, lane, canonical
effect chain and GRADE_VERSION (the existing digest of the Postpro renderer
sources and Dilla analog core). Chain sidecars record the identity as take_id;
preset sidecars retain their existing schema. Canonical Hash key ordering makes
equivalent recipes produce the same ID. Changing the source, seed, take number,
recipe or grade digest changes it. Invalid/non-finite recipe values are rejected.

The implementation remains Postpro-owned. A universal STUDIO inventory was
not introduced: Dilla, LoRA and Postpro produce into different ownership roots,
and Postpro may write beside arbitrary source photographs. A partial cross-tool
listing would falsely imply completeness.

Files: STUDIO/postpro/constitution.rb, STUDIO/postpro/lib/sidecars.rb,
STUDIO/replicate/test/postpro_cli_contract_test.rb,
STUDIO/postpro/README.md.

Commits: 61f01e455c66ad69066cdde413ae9babb5ad65f2,
86159014b1c6786fdab1ddac3c76598b1edf4cfc,
6def5bd23e5a7609913b0cae82f33464129b9c9f,
50758a8bb84b2d2494701253ba9defd42f062124;
regex correction: a4107fe8eaef0f0f1b3d6a5b843e80110a1ec02c,
b24069ec1176a3471a40b6cafa2905a6f23248dc.

### BIZ — source-bound print receipts

BIZ/tools/paths.mjs now owns PUBLISHED_INPUTS, the single document-to-source
manifest shared by bp_print.mjs and bp_index.mjs. The manifest covers
editable plan sources, content modules, build/retemplate/check tools, the
shared path contract, and print tools. It covers the published plans and guide,
the scratch-only drafts, the archived source pairs, and FETAT's builder/image
inputs according to each owner's production path.

The printer emits biz.print.v2 receipts. Each receipt binds the source HTML,
all unique declared source inputs, PDF and cover PNG by SHA-256. It captures
source digests before rendering and checks them again afterward; a changed
input prevents the receipt from being issued. The index requires exact source
manifest keys, verifies every current source digest plus the published media
digests, and retains the existing mtime, page geometry, raster-count, byte-size
and explicit NOT_REVIEWED gates. Shared inputs appearing in both HTML and
PDF dependencies are deduplicated consistently between printer and index.

The published pairs have not been regenerated. Existing biz.print.v1
receipts do not satisfy the new gate; after the operator-reviewed scratch
release is copied to the existing owner directories, rerun the index. A print
receipt is evidence of bytes and renderability, not approval of appearance or
accessibility. Draft plans remain unpublished.

Files: BIZ/tools/paths.mjs, BIZ/tools/bp_print.mjs,
BIZ/tools/bp_index.mjs, BIZ/README.md.

Commits: 15d8f5fce0920dc941a0a5a38997efb75f031366,
fa04b837dc597afe4d42665c39120ad674391a20,
031b226872ee9412f8c821d5c19457d01018877f,
cefa78e8d961fecf5da6bacd7c74ab25b381bb21,
b62344aa0fc986d1984a3e680d1b43078775dadb,
125502b7803883789eae94dbd71b506a85feaf64,
c0127559727fd8e0ae328961bff79f6fd7d0bf69.

### MASTER — browser effect approval and lifecycle scope

The Core browser effect is now approval_required, not merely policy_gated.
A one-shot rendered page visit executes page JavaScript, and even same-host GET
endpoints may mutate remote state. The Constitution therefore requests
operator approval before the effect reaches World; a missing approval surface
fails closed. The model contract and CoreBridge comment now state this boundary
and do not describe GET/HEAD-only transport as read-only.

The browser URL is included in the effect-lifecycle scope, allowing the
existing observer to store a scope digest without persisting the raw URL.
The existing no-secret rule still scans browser URLs. No login, click, form
submission, credential-entry, POST or cross-host permission was added.

Files: MASTER/lib/core.rb, MASTER/lib/core/fold.rb,
MASTER/lib/core/model.rb, MASTER/lib/cli/core_bridge.rb,
MASTER/test/test_core_reversibility.rb.

Commits: ed4440fe1bbb22ae27d7389d2a57749a5f9e3dcc,
8f6d318beead35da961280f1797ae0f46474ad3c,
fa60ffa843e77ea0cae0bb9d7a8f714932cc0b92,
a64708d58b9cbfef261e3be155e3070e69008fd0,
602f4f94bc8748bec84e682f1668fa55342a07ba,
3d6e39f91080ea3357114ebf76fdfbd39837a0a5.

### Execution boundary for Phase 16

RUN:
- GitHub read-after-write inspection of every changed file and returned commit
  references.
- Ruby 3.3.8 isolated harness for the Postpro identity implementation: PASS.
  It accepted a valid 64-character digest, produced a stable identity under
  reordered recipe Hash keys, and changed the identity when source, seed, grade
  version or take number changed.
- Local runtime discovery: Ruby 3.3.8 and Node v22.16.0 are installed.

NOT_RUN:
- The actual STUDIO/replicate/test/postpro_cli_contract_test.rb Minitest suite,
  cd STUDIO && rake test, rake check, full Ruby syntax census and
  MASTER/tools/agent_context.rb --json --tree.
- node --check on the actual BIZ modules; the BIZ build/check/print/index
  chain; fresh source-to-PDF generation; published index validation; full-page
  raster comparison; visual or accessibility review.
- The actual Core reversibility/world/bridge test suites, full MASTER checks,
  browser process attach/teardown, adversarial live-network probes, browser
  cancellation and screenshot-to-vision handoff.
- Legal-source verification, governed repository-wide /fix, OpenBSD deployment
  and live-host acceptance.

Blocker: the local checkout cannot be refreshed because this environment's
git ls-remote cannot resolve github.com. GitHub's contents/commit interface
was available for path-scoped changes and read-back, but it does not execute
the repository's hooks, tests or build tools. The Postpro identity regex was
corrected after read-back found it over-escaped; the current source and
regression now use the proper Ruby beginning/end anchors. No project test,
rendered approval or deployment is claimed.


## 14. Phase 17 — Dilla fingerprint-gated WAV reproduction — 2026-11-22

Status: CLI and replay implementation are on main; the replay method fragment
passes Ruby syntax parsing. The actual seeded render/replay integration test,
full STUDIO suite and audio comparison remain NOT_RUN.

### Contract

Dilla renderer/catalogue version is now 4.3.0. New provenance records exact
Ruby version, engine and platform; the renderer SHA-256; the exact relative
inventory and SHA-256 of dilla.rb, analog_core.rb and every data/*.json file;
and the selected progression, sample status, performer and render flags.
The source catalogue version is aligned. The tracked November 13 render and
its 4.2.0 sidecars are retained unchanged as historical creative output.

New provenance also hashes its quality and session sidecars. The Dilla
reproduce command verifies the exact source inventory and digests, Ruby
runtime/platform, original WAV bytes/hash, session/quality sidecar bytes/hashes,
seed, progression and performer before it opens the new output path. It
reconstructs effective render settings from the existing session/provenance
records, preserves seeded performer selection and suppresses ambient
SAMPLE_LOOP so the replay host cannot silently add an input.

Usage:
    ruby dilla.rb reproduce /path/to/take.provenance.json --out /path/to/replay.wav

Only the WAV master is reproduced. Supported original modes: render, random
and showcase. MIDI, MP3 and video companions are intentionally not regenerated.
Sample-flip takes are refused because the old provenance lacks an FFmpeg
decoder fingerprint and a recorded rights attestation. Older 4.2.0 provenance
is refused because it lacks the new runtime/platform and sidecar-hash contract.
Output is always a new path; source WAV, session, quality and provenance are
never overwritten by the replay operation.

The result is BYTE_MATCH or BYTE_MISMATCH against the original WAV SHA-256.
BYTE_MATCH proves byte identity for this render only. Listening remains
NOT_REVIEWED; this command does not certify taste, quality, source rights or
publication approval.

Files: STUDIO/dilla/dilla.rb, STUDIO/dilla/data/dilla.json,
STUDIO/replicate/test/dilla_test.rb, STUDIO/dilla/README.md.

Commits:
8cf2a794da9f1a94b28110378126a66f9cbdc594 (fingerprint-gated WAV replay);
a39c22155e325fc118f766db7481c8f8140b6186 (suppress ambient sample input);
92a361ed8454000233d24e302dabfb3f29e39106 (seeded replay and refusal regression);
94a5a450e8c3f0037972c875033fdd8259825d6c (replay documentation);
cbdfa0e6a70e809fb2803753e5b3caeccf713018 (Ruby engine/platform pin and malformed-sidecar checks);
fc4526dc33fe2ee8c1d605879e027ea8d7757aed (correct digest regexp anchors);
e2b351a3b9671e70c95fc06672cef847eed3899c (catalogue version alignment);
2fa15d6cbeabb839d732ab0128bbd3da9a536f56 (replace stale no-replay documentation);
98d46d4e6b21a26bd8dda9342c6fd95bba453fc0 (runtime and catalogue version regressions);
7da4de318078f8b8d1fc249d47c802de952fbb8b (refuse sidecar tampering and original-WAV overwrite).

### Execution boundary for Phase 17

RUN:
- GitHub read-after-write verification of the Dilla implementation, test,
  catalogue and README.
- Ruby 3.3.8 syntax check of the complete extracted reproduce_render method:
  PASS (ruby -c -).
- Local runtime discovery: Ruby 3.3.8 and Node v22.16.0.
- Previous isolated Postpro identity and BIZ source-digest smoke harnesses:
  PASS (recorded in Phase 16).

NOT_RUN:
- The actual Dilla one-bar render/reproduce byte-match regression.
- ruby -c STUDIO/dilla/dilla.rb and the complete STUDIO Ruby syntax census.
- cd STUDIO && rake test, rake check, focused Dilla and Postpro tests.
- Actual audio byte comparison, manual listening, sample-based replay,
  external encoder pinning, MP3/video reproduction and live provider work.
- The full repository agent-context, governed /fix, browser live journeys,
  legal-source verification, PDF visual/accessibility review and OpenBSD
  deployment remain NOT_RUN as recorded in earlier phases.

Blocker: no local pub5 checkout can be refreshed because the sandbox cannot
resolve github.com. GitHub source writes and read-back worked, but no repository
hook, Minitest/Rake suite or real audio render ran. The replay implementation
must be validated by the actual one-bar integration test on a compatible
checkout before treating Dilla reproduction as operationally accepted.


## 15. Phase 18 — LoRA spend approval, terminal metrics and private batch ledger — 2026-11-22

Status: the source, tests and owner documentation are on main and were read
back. No provider training job was created. The actual Ruby/Minitest/Rake
suites and live cancellation path remain NOT_RUN.

### Provider facts and billing basis

The pinned trainer is
replicate/fast-flux-trainer:080f17375c73ef43e1009da9d560ab5f935176c61a0c7a88866c8b8387057675.
The trainer page was checked on 2026-11-22 and states 8x Nvidia H200 hardware
at USD 0.0122 per second:
https://replicate.com/replicate/fast-flux-trainer/train

The Replicate HTTP API documentation states that terminated trainings
(succeeded, failed or canceled) include metrics.predict_time, the CPU/GPU
compute seconds used by the training. It also documents a distinct training
create and cancel endpoint. Its Cancel-After header is documented for
predictions; it is not documented as a guaranteed training deadline:
https://replicate.com/docs/reference/http/

The billing record therefore uses the pinned trainer rate multiplied by
provider metrics.predict_time. The result is explicitly labelled
CALCULATED_FROM_PROVIDER_PREDICT_TIME_NOT_INVOICE. The calculated USD amount
rounds upward to six decimal places to avoid understating measured use. It is
not a card invoice, settled charge or substitute for the Replicate account's
actual billing record.

### Approval and batch control

STUDIO/lora/train.rb now requires an explicit --approve-spend-usd value for
every training batch, including --all. The default CLI example is:

    ruby STUDIO/lora/train.rb --all --approve-spend-usd 5.00

The total approval is shared across the sequential batch. Before package
uploads or provider training creation, the runner validates the positive finite
USD value, checks the timeout is in 1..86400 seconds, and verifies that the
budget can reserve the configured minimum compute window plus its local margin.
The 60-second minimum reservation and 10-second margin are local policy
settings, not Replicate model minimums or provider guarantees.

For each job, the client-side wait timeout is bounded by the remaining
approved amount at the pinned rate and the operator timeout. On timeout, the
client requests cancellation and fetches the training again. It does not
describe cancellation as successful unless the provider status is canceled.
If the provider is still starting/processing or the final status cannot be
read, the batch stops before the next subject and reports SPEND_UNVERIFIED.
A training that completes during the cancellation race returns its terminal
record. Failed and canceled terminal records are also returned with their
metrics so measured compute is not discarded.

This is a client-side timeout/cancel guard, not a provider-enforced hard USD
cap. A job may continue to incur charges if the provider does not complete
cancellation. A measured overrun reports BUDGET_EXCEEDED and stops remaining
jobs. The local lock and ledger coordinate one checkout only; they do not
serialize another clone, device, account operator or external Replicate job.
The README expressly warns against concurrent training from another checkout.

The existing MiniMax H3 reservation remains a separate process-local per-run
estimate in STUDIO/replicate/models.rb. It is not a daily or account-wide cap.
The image/audio catalogue contains paid rows without verified per-model rates,
so these paths are not counted as zero-cost and have not been represented as
covered by the LoRA ledger or video reservation. A genuinely shared all-provider
ceiling requires authoritative rates for each paid model and a single durable
reservation/settlement owner; no duplicate authority was introduced here.

### Private evidence

The runner preflights a private mode-0600 append-only JSONL receipt at
STUDIO/lora/.cache/training-spend.jsonl before its first provider operation.
Each completed or partial batch appends schema
studio.lora.training_spend.v1, including approval, rate/source/date, measured
seconds, calculated cost, remaining amount, batch status and sanitized result
fields. Provider error bodies and signed upload URLs are excluded. The local
training-spend.lock is mode-0600, singly linked, owner-only and opened with
NOFOLLOW; the ledger is also singly linked, owner-only and opened with
NOFOLLOW. The open descriptor's device/inode is compared with the current path.
A lock file or ledger symlink is refused.

Successful per-subject candidate manifests also carry their billing record.
Failed or budget-stopped runs remain represented in the batch ledger even
when no candidate version was produced. Neither record is called an invoice.

Files: STUDIO/lora/training_standards.yml, STUDIO/lora/train.rb,
STUDIO/replicate/client.rb, STUDIO/replicate/test/lora_training_test.rb,
STUDIO/replicate/test/replicate_client_test.rb, STUDIO/replicate/README.md.

Principal implementation/test/documentation commits:
8473ef8c7ac25fc7a71169d6d9bcc6207162695c (pinned rate);
8a7517b8dad138ecc6e70739017a77505ae60668 (required approval and batch guard);
cbbc841013daa5248c59dd222208a03f4cd9f47d (preflight error boundaries);
ffc372e5224c390490bf3a93f6867deef93300cd (budget and compute tests);
87c665ed6e2d669dd35c0f1c76ddfe1bb02c5709 (verify cancellation with provider);
812a8d44ca39aefe078bfb4b7bc608d3ee1d0c5b (cancellation tests);
c131f2b936cd67513d1b3078a16b6f575468f59a (private append-only ledger);
a19d75e3474780bf3485495517a3c45389a1afb0 (ledger tests);
295f32742019197a2352d194a324181ea77ec2da (no-follow lock and inode check);
6d15f97791bb819afd1ba81786149a630e33d6c1 (lock symlink regression);
05e2407cffebb374d175ed240cf81b4a6825ae2e (training CLI documentation);
b1a4feac53024efbef604c1bf9efea787645cafb (ledger documentation);
ed75aa79200e4201c4793f35c9a70691aa5269bf (retain terminal provider metrics);
c97f367fe139b0c30cb4c1ab299ea6b27d3dab99 (persist cancellation state);
831d3681d6246afa1b425d3f720afed7dc37e0e4 (terminal status metric tests);
3bb0c87c31fad7eb14c87bd418999f43406faacd (label client-side guard);
d47b5744bc5fe9a4cd347529d41499cac185fe7a (correct hard-cap documentation);
d8b9c53fbc880ff792e79c5549d728bffc365b62 (name local reservation floor);
4003a50474b411eb561c0fdd5381f59291934fa8 (billing policy provenance);
fed1da352f61d05947b39e573ddb64acdfe8b503 (pre-dispatch wait bound and upward cost rounding);
0ac4b663279a5e6b9dc2011e742fa810cd91630f (timeout, rounding and terminal-cost tests);
dcdeadc7b5d7bcee31ef237c8d2d4d2b524fb2ac (local reservation documentation);
31c473bce4054e60763d5842827e04c045aa1880 (batch ledger and guard assertions);
06a3eba001c7932711a67b2893b7de6f732e15e9 (terminal response contract comment).

### Execution boundary for Phase 18

RUN:
- Official Replicate trainer page and HTTP API documentation inspected for the
  pinned hardware rate, terminal training metrics and Cancel-After scope.
- GitHub read-after-write inspection of the billing standard, runner, provider
  client, focused tests and owner README.
- Ruby 3.3.8 and Node v22.16.0 runtime availability confirmed.
- Local no-follow flag availability confirmed on the Linux sandbox.

NOT_RUN:
- The actual STUDIO/replicate/test/lora_training_test.rb and
  STUDIO/replicate/test/replicate_client_test.rb Minitest suites.
- cd STUDIO && rake test, cd STUDIO && rake check, full Ruby syntax census,
  MASTER/tools/agent_context.rb --json --tree and governed /fix.
- A real Replicate training create/cancel/status cycle, actual provider usage
  metrics, paid-cost comparison, account invoice reconciliation and
  cross-checkout concurrency test. No training or paid provider request was
  launched in this phase.
- OpenBSD-specific file-lock/no-follow proof and a real private home directory
  permission audit.

Blocker: this execution environment has Ruby 3.3.8 and Node v22.16.0 but cannot
resolve github.com for git ls-remote or a checkout refresh. GitHub contents
writes and read-back were available; repository hooks and project tests did not
run. Do not mark training spend safety as runtime PASS or treat the calculated
receipt as actual billing.


## 16. Phase 19 — blocker reduction and staged acceptance — 2026-11-22

Status: blocker classification and scope documentation are updated on main and
read back. This phase changes no live service, payment, DNS, account, privacy,
rights or production acceptance claim. Runtime/project checks remain NOT_RUN.

### Reduced implementation blockers

The four rows previously marked status: blocked in MASTER/data/gaps.yml are now
status: open, each with a bounded preparatory stage and an exact remaining
external acceptance gate:

- messenger_webrtc_calls: open for call-session lifecycle, ActionCable
  signaling, permission/teardown UX and local/same-LAN ICE tests. Host STUN/TURN
  and real cross-NAT tests still gate reliable production media.
- marketplace_contact_relay: open for privacy-preserving in-app contact using
  the existing buyer/seller conversation, masking and reviewed reveal. Inbound
  mail aliases/forwarding still need vm23 MX/relay routing.
- tv_live_stream_infra: open for provider-neutral ingest/delivery contract,
  loopback adapter, readiness/failure checks and runbook. Production media
  server/transcoding/delivery remain gated on the selected host infrastructure.
- amber_weather_suggestions: open for deterministic suggestions over an
  injected weather snapshot and a no-weather fallback. A live forecast provider,
  freshness and attribution remain separate integration gates.

The gap ledger now has zero rows with status: blocked. Open does not mean built,
picked, deployed or accepted; each row remains subject to its existing
ideation/pick/workstream and Law-gated implementation path.

RAILS/apps.yml no longer marks the local TV live adapter stage or Amber's
injected-weather stage as agent: ignore. Their entries remain status: planned
and spell out that only local preparatory work is open. Other planned features
that depend on architectural migrations, unpicked design decisions or external
capability remain under their existing fences.

RAILS/apps.horizon.yml now clarifies that an explicit operator request can
authorize a named preparatory slice (contracts, fixtures, adapters and local
tests) without promoting the whole aspirational feature to active or production
ready. Its global agent_policy: ignore remains the default for unrequested
full-feature implementation.

### Narrowed external acceptance gates

The old Section 5 has been replaced with 16 named external acceptance gates.
For each, the local/contract/test/fixture work that can proceed without the
missing external material is named separately from the live-production claim.
This covers WebRTC, marketplace contact relay, TV ingest, ActivityPub,
tiles/licensing, provider-staging payments, real-device PWA, SEO crawl,
accessibility participants, live journeys, OAuth callbacks, radio/Whyp,
operator alert relay, registrar DNSSEC, off-host backup/key recovery and
production CSP/egress enforcement.

MASTER/data/operator_seams.yml now states that a seam blocks only the live
claim whose evidence it names. It is not a global work-stop flag: independent
source changes, local/contract tests, dry-runs, adapters and failure-path proof
must continue. The exact live evidence remains mandatory.

Hard protections deliberately not relaxed:
- subject consent, source rights and human likeness/publication approval;
- paid-provider spend approval, private ledgers and truthful provider billing;
- payment-provider staging and signature/idempotency proof before real money;
- OAuth state/nonce/PKCE and secret-store requirements;
- DNSSEC registrar DS publication and recovery proof;
- off-host backup and key recovery;
- production CSP/egress allowlisting and rollback;
- truthful PASS/DELIVERED status, real test output and human accessibility,
  audio or visual acceptance where the claim requires it;
- the horizon default against silent implementation of unrequested features.

Files: MASTER/data/gaps.yml, MASTER/data/operator_seams.yml,
MASTER/data/receipts/handoff-2026-11-22-next-agent.md,
RAILS/apps.yml, RAILS/apps.horizon.yml.

Commits:
b69a07c43b13be51d12e86e2fb3c5a07e89ef0d9 (open the four staged gap slices);
e06f174d93b9aa6386caee413ea6101a8235fb90 (operator seams scope);
7341cfcd81f481436e166b31744a074a70842fd5 (external gate reclassification);
9a573afa2567af8a9dd0531fb215c97efab2841a (TV and weather local stages);
32b3a465cb2f27e4e15bf7f77613f48334bf35f6 (explicit preparatory slice under horizon fence).

### Execution boundary for Phase 19

RUN:
- GitHub read-after-write checks for the four gap rows, operator-seam contract,
  apps.yml feature rows and horizon policy wording.
- Gap registry scan found zero remaining rows with status: blocked.
- Read-back confirms all 16 external gates are still explicitly listed in
  Section 5 with local preparation and remaining production acceptance split.

NOT_RUN:
- The actual Rails app tests, MASTER gap/schema validations, Law checks,
  full /fix, local browser journeys, same-LAN/cross-NAT calls, live TV ingest,
  Whyp import, external OAuth, provider staging, real-device PWA, accessibility
  participant review, registrar DS updates, off-host restore and vm23 enforcement.
- No external service was installed, paid, enabled or contacted by this phase.
- No previously unrequested horizon feature was promoted to picked or done.



---

## Phase 20 — Uninterrupted mission and backlog recovery

Objective: a dependency, provider outage, failed task or incomplete delivery receipt
must stop only its own objective. Independent authorised tasks continue through
the existing single-writer mission lease and owner registry. No second task queue
or parallel writer was introduced.

### Mission recovery

- Removed the lifetime five-attempt automatic continuation cutoff. Attempt count
  is history, not a permanent lockout. Retry delays still use bounded exponential
  backoff capped at one hour; exhausted providers re-probe at the maximum delay.
- The existing failure taxonomy now handles both raised exceptions and returned
  error results in TaskSteward. Transient failures wait and retry; exhausted
  providers pause and re-probe; permanent failures terminate only that mission;
  ambiguous outcomes require human review.
- Timeout and common network-interruption phrases are included in the transient
  fallback vocabulary. Exhaustion remains a separate category and is matched
  before transient errors.
- A blocked mission is returned with its actual durable record. The existing
  `ensure_queued!` API permits replacement of that exact blocked objective only
  when the caller explicitly supplies `resume_blocked: true`.

### Backlog isolation and progress

- The owner-registry executor parks an interrupted, failed or future-waiting
  backlog item in the same private state store as mission records
  (`MasterPaths.fix_state`; local `.master/backlog-executor.jsonl` when no
  remote identity is available). It keeps the item identity/digest, mission identity, classification,
  retry time, scope fingerprint and operator-release requirement.
- The executor advances to other independently eligible owner-registry tasks
  while a parked item waits. A retry becomes eligible at its due time; a scope
  change can invalidate an automatic park; human-review parks require the
  explicit `Executor#resume_item!` action.
- A completed mission without a valid executor delivery receipt is recorded as
  `completed_unverified` and parked for review. It is never inserted into the
  completed-receipt set and cannot be mistaken for accepted work.
- Receipt storage refuses unsafe `.master` directories, symlinked receipt files
  and permissive file modes. A failure to persist the park record reports
  `delivery_failed` rather than silently advancing and losing recovery state.
- The backlog runner claims its mission lease before validating the owner record
  and target. An idle steward does not block a live lease owned by another process.
  A returned run with no terminal status is not promoted to completion.
- Adaptive journey selection falls through to independent ready candidates only
  when every route in the strategic priority band is waiting on unsatisfied
  dependencies. If any strategic route is ready, the existing priority policy
  continues to own selection.

### Changed owners

`MASTER/lib/fix/mission.rb`, `MASTER/lib/fix/mission/state.rb`,
`MASTER/lib/fix/mission/run_state.rb`, `MASTER/lib/fix/task_steward.rb`,
`MASTER/lib/fix/adaptive_journey.rb`, `MASTER/lib/fix/constants.rb`,
`MASTER/lib/ground/failure_taxonomy.rb`, `MASTER/tools/owner_registry_tasks.rb`,
`MASTER/lib/boot/master_boot.rb`, and their focused tests under `MASTER/test/`.
The execution policy summary is in `MASTER/README.md`.

Representative commits on main:
- `bfaaaa48583353208401ecc3cef4e20e674cd34c` — remove lifetime attempt ceiling.
- `f7276dd57c469d1423c9e25302218e794af5d8cc` — classify task failures and notify scheduler.
- `e061551daf7cf20665a0a4a9e1951b18e84a0802` — select independent ready work around parked dependencies.
- `6f5144c65efa03dfbeaaf89caf7a0b3cf540ce27` — park failed backlog tasks and continue.
- `bd35c4ccdea5487cf683601b681e06d14ea6bec8` — settle backlog failures through the shared taxonomy.
- `50ce329e277dc47d6e6c045d458f29c654fc1cda` — classify returned errors as well as exceptions.
- `87515da5fc143c7058b55839f631be1648e0c243` — park unverified terminal work without stalling the backlog.
- `f53e8f64b5bdeef15e30ca135fd433219621fd83` — regression test missing delivery proof with independent work.
- `f874271b52cc8c0550048e65bcdbf35d2671badb` — keep the unverified-completion parking API minimal.
- `48e01a900933eaf297906f59aefc033476892158` — preserve MASTER's intentional restricted group grant on private state directories.
- `b28ed1f42317a0da6d662e254a049f784f8f3f47` — keep permanent failures parked for explicit release.
- `563b2202bdee52b050f7b70fb642d8ae3ba8fdc2` — make a permanent failure's stored reason authoritative for downstream classification.
- `6c186498b64a6823c90fe97f0f12055d71a96fb3` — assert the authoritative reason in the TaskSteward regression test.
- `84547a1dc1509fe4101d0bab027ae6acd0c474ac` — reject hard-linked backlog receipt files.
- `7d21ce155958023250564f4e50443121a26e2312` — allow the assigned Rails group to append private receipts without opening access to others.
- `becd8b98f0dc015f7cedf89d7b60fe6ae983926d` — test the private receipt group-access boundary.

### Operator flow-control surface

- `bin/operator backlog status` is the read-only view of current mission,
  eligible/ready/completed counts and parked item classifications/retry times.
  It deliberately omits task prompts and raw exception bodies.
- `bin/operator backlog resume <item-id>` validates that the source item still
  exists and remains eligible, then records an explicit release event only for
  a parked item requiring operator review. It does not mark work complete or
  bypass the original acceptance proof. If another single-writer mission is
  active, the released item waits for the next eligible selection.
- The status API uses the existing owner registry and receipt stream; it adds
  no task ledger or duplicate backlog.

Additional commits on main:
- `687050ca303320c5a5d1a0be2be02b6d14a782cf` — add the read-only status
  projection and validate explicit resume targets.
- `9ee475bb6cbb59791f72654cd2ed3073968f70fd` — test status redaction and
  ready/parked counts.
- `7b2412a115af87ceee063b071967e4b9795c8f9b` — declare the Set dependency
  used by status.
- `d4b40396e850460b4124ff4f6cca79625cf733a2` — bind the status test to the
  real parked-scope fingerprint.
- `0d26c4c6e49262a96b24200d758dc5c8df00d84d` — pin the operator backlog status/resume command surface.
- `e7df083a927478215a645d5e296f7b36069363eb` — test that adaptive scheduling stops when no route has satisfied dependencies.
- `df5457dda334b3378003e643d3cac6d64fc5b943` — remove a duplicate read-only status test after retaining the stronger parked-count/redaction regression.
- `8634ad75975972640718726559c73ed7d41da0bc` — concurrent browser lease
  shutdown revocation change; unrelated to backlog recovery, included in
  the verified branch tip.

### Lease takeover fencing

- Mission retry, human block and permanent failure mutations accept the
  observed mission ID and lease owner. When scheduler recovery supplies those
  values, the write lock re-reads the current record and rejects a changed
  mission or lease with `Mission::Fenced`.
- TaskSteward passes the identity/lease snapshot it observed into each
  classification outcome. A worker that lost its lease cannot defer, block or
  fail the successor's mission; the current owner remains responsible for it.
- Normal claimed mission handles retain the existing write fence. This adds a
  fence to the supervisor's unclaimed recovery path without weakening the
  single-writer model.

Lease-fencing commits on main:
- `7bc400f736a60a6715a7cce8fde603c3d4acb833` — enforce lease fencing on defer and block.
- `7f9b5478abe05990f916441e29d6c40bd20f85ac` — test lease fencing on mission recovery writes.
- `2963701af33485ed6a81c3b65053cd3d630a9bc3` — compare expected mission identity and lease under lock.
- `a162e1308fbfcb221e421c5c77bdb1b558908d6c` — pass observed mission lease identity into recovery settlement.
- `0a001412d6e57c0b318b473bbd0cd2a62d17b3f7` — preserve explicit `Fenced` outcomes.
- `9d7b79cec0017fba202fe18ccc76c98cc6105c65` — test conditional scheduler recovery fencing for defer, block and fail.
- `7434c8a7dc20c0ff2be15765f1252ca1b278f71e` — fence the unverified backlog completion handoff with mission ID and lease owner.

### Phase 20 evidence boundary

READ_BACK:
- GitHub read-after-write completed for all changed implementation, test,
  operator and documentation files. The latest verified implementation HEAD
  before this receipt amendment was `df5457dda334b3378003e643d3cac6d64fc5b943`.
- Permanent terminal failures overwrite any stale transient wake reason, so
  parked-item receipts retain the final failure classification.
- Receipt-directory checks follow the private-state contract: the owner uses
  `MasterPaths.private_dir_mode`; a non-owner must be a member of the assigned
  group, owner access remains intact, group write/execute are required for the
  append, and all other access is denied. Receipt files are singly linked,
  symlink-refusing, owner-only mode 0600.
- The new append-only parking receipt uses the existing
  `MasterPaths.private_dir_mode` policy: no access for others, owner access
  retained, and an explicitly assigned foreign-group grant preserved for the
  vm23 MASTER/Rails hand-off. The receipt file itself remains mode 0600.
- Focused regression tests were added for attempts beyond the former ceiling,
  transient/exhausted/permanent/ambiguous outcomes, returned Result failures,
  explicit blocked-mission resume, dependency fallback, ordinary backlog parking,
  human release, and unverified completion continuing to independent work.

NOT_RUN:
- No Ruby test file, Rake suite, Law assessment, full `/fix`, backlog autorun,
  rendered browser check or production deployment was executed in this phase.
- Worker-count/resource adaptation was deliberately not changed: no current
  CPU, memory, provider-latency or quota profile was collected to justify
  changing the existing worker and semantic budgets.
- No external credential, provider, paid call, production host or live service
  was contacted or changed. PASS and production readiness remain unclaimed.

### Phase 20 follow-up — operator release and recovery fencing

Subsequent mainline changes tightened the handoff and made its recovery controls
reachable from the existing operator interface:

- `MASTER/bin/operator backlog status` exposes ready/parked/completed counts,
  the current mission state and retry timing without printing prompts or raw
  exception bodies.
- `MASTER/bin/operator backlog resume <item-id>` validates that the owner
  record still exists and remains eligible, then appends an explicit release
  event for a human-review park. It does not create completion proof.
- A future-waiting backlog mission may hand off to independent work only while
  `auto_continue: true`. Explicitly disabled missions do not trigger an
  unattended handoff.
- Mission recovery writes from TaskSteward carry the observed mission ID and
  lease owner. The write lock re-checks both before defer, block or fail.
  The unverified-completion callback applies the same identity fence.
- Adaptive scheduling now has a negative regression: when no candidate has
  satisfied dependencies, it stops rather than inventing a runnable task.
  The independent-work fallback applies only when a separate ready route exists.
- Duplicate status coverage was removed after a stronger fixture already
  covered parked counts, prompt redaction and a live scope fingerprint.

Additional commits:
- `2ea6017e3019964ce877ce41f7132bd0103d695c` — operator backlog status/resume.
- `332c7cc0549df230681e86bdd60fe904a91cc35f` — do not hand off disabled missions.
- `0062a9220abc904f578ce845b2e9f1f244e8e982` — test future-waiting handoff.
- `687050ca303320c5a5d1a0be2be02b6d14a782cf` — status projection and resume eligibility.
- `7bc400f736a60a6715a7cce8fde603c3d4acb833` — fence defer/block on claimed writes.
- `2963701af33485ed6a81c3b65053cd3d630a9bc3` — fence scheduler settlement by mission ID and lease.
- `a162e1308fbfcb221e421c5c77bdb1b558908d6c` — pass the observed lease snapshot into recovery.
- `0a001412d6e57c0b318b473bbd0cd2a62d17b3f7` — propagate explicit fenced outcomes.
- `7434c8a7dc20c0ff2be15765f1252ca1b278f71e` — fence unverified-delivery handoff.
- `0d26c4c6e49262a96b24200d758dc5c8df00d84d` — test operator status/resume exposure.
- `e7df083a927478215a645d5e296f7b36069363eb` — retain stop behavior when no route is ready.

READ_BACK:
- The updated mission, TaskSteward, Backlog::Executor, MasterBoot, operator
  command, README and focused test files were read back from `main`.
- Latest implementation/test changes were present on `main` at the time this
  addendum was prepared.

NOT_RUN:
- Ruby tests, Rake suites, Law scans and the complete repository `/fix` remain
  unexecuted in this environment. No PASS is claimed from source read-back.
- No vm23 deployment, production action, external provider call or paid work
  was performed.
