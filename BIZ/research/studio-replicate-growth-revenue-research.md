# STUDIO × Replicate — user growth and revenue stream research

Written 14 November 2026, after reading the Replicate catalogue STUDIO already carries
in `STUDIO/replicate/models.yml` (every schema there was read live from the Replicate API
on 2026-11-13) and cross-referencing the pub5 family: the six RAILS apps, MASTER's law
engine, and the billing/affiliate/blocks that already ship. Everything marked *estimate*
is an estimate; everything else cites a file in this tree or a live model schema.

The question this answers: the selfie pipeline can render a real person's likeness into
still films and styles — what turns that into users and revenue without breaking the
family's laws (media stays out of git, likeness work is consensual, master-speech and
dilla stay operator-owned)?

## What the pipeline can already do (source of truth in the tree)

- **Likeness**: `johann-flux` and `ragnhild-flux` are trained, pinned LoRA versions
  (`STUDIO/lora/{johann,ragnhild}/replicate_training.json`, ragnhild deliberately pinned
  to the Sep 15 weights because the Oct 10 run overfits and loses likeness). The default
  engine is `google/nano-banana` (reference-photo likeness, no training run) with a
  fallback chain ending on Replicate's free tier, so a render never dies for want of
  credit.
- **Film**: `minimax/h3-lite` is the default film engine — first/last-frame
  image-to-video, 4–15 s, 480P/768P — with Kling v3 Omni and the rest of the
  `image_to_video` catalogue behind `--film-engine`. STUDIO lays its own dilla bed under
  the cut rather than paying for model audio.
- **Style passes**: the four look models STUDIO catalogued are the purchasable looks —
  `levelsio/disposable-camera` (trigger STL), `levelsio/analog-film` (trigger ANLG),
  `fofr/kontext-ps1`, `fofr/kontext-old-and-damaged` (damaged print), plus
  `fofr/kontext-make-person-real` as the realism pass that trades the plastic AI face
  for skin texture. The last three take the subject's own LoRA through `extra_lora`,
  so a styled selfie keeps the face.
- **Craft gate**: `SELFIE_DEPARTMENT_RECIPE` and its children in `MASTER/data/laws.yml`
  (one coherent recipe per shot, one authoritative development, contact-sheet review)
  are what keep the output sellable rather than a filter stack.
- **Billing rails**: `RAILS/__shared/config/plans.yml` is a live Stripe-planned billing
  reader (brgen business presence NOK 399/mo, amber premium EUR 7.99/mo/69.00/yr,
  MASTER law-API tiers USD 49/299 per month); entitlements gate by name, not plan key.
- **Distribution rails**: affiliate in-feed units (`Shared::Affiliate`,
  every-N-posts band), `rake growth:report` (first-party signals, no per-request
  identity), PWA offline surfaces in every app, sitemaps and feeds already generated.

## Seven revenue streams, ranked by distance from what already ships

1. **Styled persona packs (sell the looks, not the pixels).** A buyer submits N consented
   reference photos of *themselves*; STUDIO trains their LoRA with
   `replicate/fast-flux-kontext-trainer` (the trainer STUDIO's own lora flow already
   targets) and delivers a pack: 12 stills, 3 shorts (h3-lite), 4 style passes
   (disposable / analog / ps1 / old-and-damaged) as web-ready files with the RAW-style
   sidecars postpro already writes. Price as *estimate*: NOK 490 one-off, or bundled as
   amber-style premium. The likeness risk is contained because the subject trains on
   themselves — the same consent shape mytoonz already encodes
   (`add_provider_consent_to_comic_strips`, 2026-11-13 migration).
2. **Style passes as a SKU on existing apps.** The four look models are one call each on
   an image the user already owns. Sell "finish your photo" as a per-render credit pack:
   disposable-camera for the brgen feed, analog-film for amber's wardrobe shots,
   kontext-ps1 as a novelty on mytoonz comics, old-and-damaged for the mrdamascy
   print-menu. No likeness work, no training, the widest funnel of the seven. *Estimate*
   NOK 19–39 per pass; the in-feed affiliate unit is the ready-made placement pattern.
3. **Video shorts tier for creators.** h3-lite at 4–15 s is the cheapest good
   image-to-video in the catalogue. Sell a monthly "series" entitlement: one selfie
   series becomes a weekly short with the dilla bed laid under it (never model audio).
   Ships on the amber_premium entitlement pattern (`plans.yml`), *estimate* EUR 7.99/mo
   — the same price the family already charges for premium.
4. **MASTER law-API as the professional product.** The only stream already priced and
   metered: `master_api_team` (USD 49/mo, 10 000 checks) and `master_api_business`
   (USD 299/mo). Growth lever: the law ladder's scan-only mode over a user's repo is a
   natural CI step; document one CI recipe and let agencies self-serve. This is the
   highest-margin stream because it sells MASTER, which costs nothing per check to run
   on free compute.
5. **brgen business presence + marketplace listings.** Already in `plans.yml`
   (NOK 399/mo, `featured_listings` entitlement). Growth lever is the gallery pages:
   STUDIO's selfie gallery pattern (`selfies.html` + generated manifest) doubles as a
   listing-photography showcase for restaurants — mrdamascy's menu photography is the
   demo. Sell the *shoot*, keep the subscription.
6. **Prints and merch (physical).** The deterministic postpro presets (Portra 400,
   tungsten, E-6, cinematic per the camera profiles recovered from pub2) produce
   exhibition-grade files; disposable/analog looks sell as "film you didn't shoot".
   *Estimate* margin 60–70% at print-on-demand; the honest cost is judging —
   `SELFIE_CONTACT_REVIEW` requires human contact-sheet review, so prints are
   labour-gated and priced accordingly (limited editions, not open shops).
7. **License the craft data, not the images.** `lora/guides.yml` is the recovered
   pub4 photography knowledge as runtime data (four-layer failure model, light
   patterns, distance rules). Competing studios pay for the *recipe* — a data licence
   with the judge thresholds (`thresholds.yml`) as the quality gate. Small market,
   near-zero cost, and it cannot leak likeness risk at all.

## User growth loops that cost nothing new to build

- **Gallery pages as landing surfaces.** `STUDIO/selfies.html` reads a generated
  manifest and nothing else — the same pattern one folder per subject turns into
  public portfolio pages (subject-filtered, screen-reader captioned, bed never
  autoplaying). Each gallery is a shareable URL that demos the pipeline without any
  paid media.
- **The free-compute fallback as a free tier.** `models.yml`'s fallback chain ends on
  flux-dev/flux-schnell (free tier), so "try the pipeline" costs nothing per render.
  A public demo that renders one prompt on the free tier converts better than any
  copy; the RG-69 beat machine already proves the family ships playable pages.
- **Feed-native distribution.** The in-feed affiliate band (`AFFILIATE_EVERY`) is the
  placement for the style-pass SKU (stream 2) — the unit is already rendered, paid for
  by affiliate deals, and measurable through `rake growth:report` without identity
  collection.
- **The law engine as content.** MASTER's 176 laws with per-law definitions are
  public-by-default documentation; each law page ends with "run it on your repo" —
  the API tier (stream 4) is one click away. Content marketing that is the product.

## What must stay true (laws and honesty)

- Media out of git: renders, beds and private likenesses never enter the repo
  (`STUDIO/README.md`); a revenue stream that requires checked-in media is rejected.
- Consent: any likeness work routes through the same provider-consent shape mytoonz
  already migrated; no third-party faces, and the two trained subjects (johann,
  ragnhild) are the operator's own studio models.
- One development per photograph: packs ship postpro's deterministic pass, never a
  random take; random sweeps are exploration only (`SELFIE_ONE_DEVELOPMENT`).
- No invented numbers: prices marked *estimate* here go through `plans.yml` with real
  Stripe prices before any checkout is offered — a plan whose ENV is unset shows as
  not available, which is the honest default.

## Next concrete step

Wire stream 2 (style passes) first: it needs one controller action per app that calls
the already-catalogued model schema, one entitlement name in `plans.yml`, and the
affiliate band as placement — no new model, no training runs, no likeness risk, and
`rake growth:report` measures it from day one.
