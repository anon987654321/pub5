# brgen

**A social network with no global timeline, because the city you live in
is the only feed that ever mattered.** brgen is one Rails process for many hosts. The host you arrive on
determines the city and the vertical you use. The app runs Rails 8.2.0.alpha
on SQLite behind Falcon, with Hotwire, Solid Queue, Solid Cache and relayd.
It listens on port 38182. Read `RAILS/brgen/AGENTS.md` before changing it.

## Brand

brgen is the city-first network: one living local identity that spans conversation, commerce,
dating, food, maps, media and messaging. The missing vowel is the brand mechanic. It makes every
city apex recognisable and leaves the place itself in charge. The verticals borrow brgen's
identity and earn a visual dialect of their own only when the surface needs one. Design values
come from MASTER/data/tokens.yml through Master.tokens, and the shared stylesheet is
RAILS/__shared/README.md. The feature matrix is RAILS/apps.yml under brgen; work only the operator
can finish is listed in `MASTER/data/operator_seams.yml`.

**Visual benchmark: X, translated for a city.** Borrow its fast conversational hierarchy:
recognisable authors, compact timestamps, readable post bodies, immediate media and reply
actions, and clear thread relationships. Do not copy its global trending model or generic
engagement loops. Brgen's feed remains city-scoped and single-column; its horizontal vertical
navigation and mobile tab bar are deliberate. Do not restore the retired left rail or add a
second row of feed-order chips. Add contextual material only when it is backed by real city
data. The city, not a global timeline, remains the organising principle.

## Cities

A city is an apex host, and the apex serves the social feed. The canonical city records
live in `config/cities.yml`; `Brgen::DomainRegistry` projects their host identity into
the stable six-field `ENTRIES` API, and `CitySeed` reads coordinates and time zones
from those same records. The catalogue contains 43 city apexes. This table documents
the full catalogue, not a promise that every domain is registered, delegated, certified
or publicly live.

| City | Country | Apex host | Marketplace host |
|---|:---:|---|---|
| Bergen | NO | `brgen.no` | `markedsplass.brgen.no` |
| Longyearbyen | NO | `longyearbyn.no` | `markedsplass.longyearbyn.no` |
| Oslo | NO | `oshlo.no` | `markedsplass.oshlo.no` |
| Stavanger | NO | `stvanger.no` | `markedsplass.stvanger.no` |
| Tromsø | NO | `trmso.no` | `markedsplass.trmso.no` |
| Trondheim | NO | `trndheim.no` | `markedsplass.trndheim.no` |
| Reykjavík | IS | `reykjavk.is` | `markadur.reykjavk.is` |
| København | DK | `kbenhvn.dk` | `markedsplads.kbenhvn.dk` |
| Göteborg | SE | `gtebrg.se` | `marknadsplats.gtebrg.se` |
| Malmö | SE | `mlmoe.se` | `marknadsplats.mlmoe.se` |
| Stockholm | SE | `stholm.se` | `marknadsplats.stholm.se` |
| Helsinki | FI | `hlsinki.fi` | `markkinapaikka.hlsinki.fi` |
| Birmingham | GB | `brmingham.uk` | `marketplace.brmingham.uk` |
| Cardiff | GB | `cardff.uk` | `marketplace.cardff.uk` |
| Edinburgh | GB | `edinbrgh.uk` | `marketplace.edinbrgh.uk` |
| Glasgow | GB | `glasgw.uk` | `marketplace.glasgw.uk` |
| London | GB | `lndon.uk` | `marketplace.lndon.uk` |
| Liverpool | GB | `lverpool.uk` | `marketplace.lverpool.uk` |
| Manchester | GB | `mnchester.uk` | `marketplace.mnchester.uk` |
| Amsterdam | NL | `amstrdam.nl` | `marktplaats.amstrdam.nl` |
| Rotterdam | NL | `rottrdam.nl` | `marktplaats.rottrdam.nl` |
| Utrecht | NL | `utrcht.nl` | `marktplaats.utrcht.nl` |
| Brussels | BE | `brssels.be` | `marche.brssels.be` |
| Zürich | CH | `zrich.ch` | `marktplatz.zrich.ch` |
| Liechtenstein | LI | `lchtenstein.li` | `marktplatz.lchtenstein.li` |
| Frankfurt | DE | `frankfrt.de` | `marktplatz.frankfrt.de` |
| Bordeaux | FR | `brdeaux.fr` | `marche.brdeaux.fr` |
| Marseille | FR | `mrseille.fr` | `marche.mrseille.fr` |
| Milan | IT | `mlan.it` | `mercato.mlan.it` |
| Lisbon | PT | `lisbon.pt` | `mercado.lisbon.pt` |
| Warszawa | PL | `wrsawa.pl` | `marktplatz.wrsawa.pl` |
| Gdańsk | PL | `gdnsk.pl` | `marktplatz.gdnsk.pl` |
| Austin | US | `austn.us` | `marketplace.austn.us` |
| Chicago | US | `chcago.us` | `marketplace.chcago.us` |
| Denver | US | `denvr.us` | `marketplace.denvr.us` |
| Dallas | US | `dllas.us` | `marketplace.dllas.us` |
| Detroit | US | `dtroit.us` | `marketplace.dtroit.us` |
| Houston | US | `houstn.us` | `marketplace.houstn.us` |
| Los Angeles | US | `lsangeles.com` | `marketplace.lsangeles.com` |
| Minneapolis / Minnesota | US | `mnnesota.com` | `marketplace.mnnesota.com` |
| New York | US | `newyrk.us` | `marketplace.newyrk.us` |
| Portland | US | `prtland.com` | `marketplace.prtland.com` |
| Washington DC | US | `wshingtondc.com` | `marketplace.wshingtondc.com` |

`CITY_NETWORK_DOMAINS` is product membership (eleven cities). `LIVE_DOMAINS` is
the smaller operator-controlled set with relayd TLS keypairs (seven city apexes at
the time of writing). Neither constant proves public delegation or a successful
HTTPS request. Check registrar state with `OPENBSD/bin/domain_watch.rb`, and public
DNS, certificate coverage and HTTPS with `OPENBSD/bin/domain_watch.rb --tls`.
The footer, search palette and mobile city navigation expose only
`CITY_NETWORK_DOMAINS & LIVE_DOMAINS`. The four network members not in
`LIVE_DOMAINS` stay out of public navigation until their DNS and TLS are verified.

## Host and subdomain map

For each city apex above, the generated DNS and certificate inventory uses these
hostnames:

| Purpose | Hostname pattern | Notes |
|---|---|---|
| City feed | `https://<apex>` | Canonical city host |
| WWW alias | `https://www.<apex>` | DNS and certificate alias; not a separate app |
| Marketplace | `https://<marketplace>.<apex>` | Localized per city in the table above |
| Radio | `https://radio.<apex>` | Canonical public host for the Playlist engine |
| Dating | `https://dating.<apex>` | Dating engine |
| TV | `https://tv.<apex>` | TV engine |
| Food compatibility host | `https://takeaway.<apex>` | Legacy host for the Takeaway engine |
| Maps | `https://maps.<apex>` | Maps engine |
| Messenger | `https://messenger.<apex>` | Messenger engine |

Food ordering's preferred URL is `https://<marketplace>.<apex>/food`.
The `takeaway.<apex>` hostname remains a compatibility mount of the same
Takeaway engine; it is not a separate Rails application.

`https://playlist.brgen.no` is an additional host for the Radio/Playlist engine.
It is an alias only on Bergen's apex; other cities use `radio.<apex>` alone.
`https://ai.brgen.no` is MASTER, and `https://mrd.brgen.no` is the Mr Damascy
application. Both are separate applications, not Brgen vertical engines.
`mail.brgen.no` is an email endpoint, not a website or vertical.

The city list above is not the whole DNS inventory. Standalone domains are managed
outside the city catalogue:

| Application or purpose | Apex host | Additional configured HTTPS name |
|---|---|---|
| Amber | `amberapp.art` | `www.amberapp.art` |
| BSDPorts | `bsdports.org` | `www.bsdports.org` |
| Other standalone zones | `pub.attorney`, `pub.healthcare`, `freehelp.legal`, `bsddocs.org`, `discordb.org`, `stacyspassion.com`, `foball.no` | Each has a configured `www.<apex>` certificate name |

A DNS zone or ACME block does not prove an application route. Use
`RAILS/apps.yml`, `OPENBSD/deploy_inventory.json` and
`OPENBSD/mirror/etc/relayd.conf` to establish the intended service mapping.
The registrar snapshot is `OPENBSD/data/domain_inventory.yml`; pending, parked,
unregistered and stale domains must not be reported as live websites.

Two stale entries require particular care: `amstrdam.nl` has been recorded as
re-registered elsewhere, and `dnver.us` is an old Denver spelling that is absent
from this city catalogue but remains in legacy DNS configuration. Neither is a
deployment target without an explicit ownership and cleanup decision.

Tenancy is `acts_as_tenant` on the city, taken from the Host header, so one deploy
holds many cities that share users and sessions but not content. The apps default
to Norwegian. Every city entry names its own language, but only two translations
ship, nb and en, so the Nordic cities get Norwegian and every other city gets English.
`brgen.no` is nb and `lsangeles.com` is en-US. A city that names Italian or Polish
is still served in English, because a page with five translated words reads worse
than an honest page in one language.

## Verticals

The host app holds the feed, communities, events, stories, direct messages and
moderation. The city-scoped engines live under `brgen/engines/` and are mounted
on the subdomains listed above. The marketplace hostname is the only translated
vertical name; radio, dating, tv, takeaway, maps and messenger use the same
subdomain labels across cities.

The engines are engines/dating, engines/maps, engines/marketplace,
engines/messenger, and engines/radio, which holds Playlist and TV. The public
Radio hostname is `radio.<apex>`; Playlist is the engine name, and
`playlist.brgen.no` is its additional Bergen host. Food ordering is the Takeaway
engine, nested inside Marketplace and served at `/food` on the localized
marketplace host. The legacy `takeaway.<apex>` host still resolves to that engine.
Messenger is an engine whose routes are drawn in the host. MASTER and Mr Damascy
remain separate applications, not verticals.

**Vertical product briefs:** [Dating](engines/dating/README.md) ·
[Marketplace](engines/marketplace/README.md) ·
[Takeaway / food](engines/marketplace/engines/takeaway/README.md) ·
[Radio](engines/radio/playlist/README.md) ·
[TV](engines/radio/tv/README.md) ·
[Maps](engines/maps/README.md) ·
[Messenger](engines/messenger/README.md).

These briefs preserve the distinct product promises while treating the active engine,
routes and tests as the authority for what is actually available.
## Marketplace integration

The Marketplace engine owns listings, stores, orders and its storefront; the Brgen host owns
city identity and the webhook entry points shared with the other verticals. The host has no
listing model. The engine's product and feature status lives in
[the Marketplace README](engines/marketplace/README.md) and `RAILS/apps.yml`.

The host serves `/merchant-feed.xml` with up to 10,000 publicly visible, priced and photographed
goods; affiliate inventory is excluded. Stripe and Vipps enter through host routes at
`/webhooks/stripe` and `/webhooks/vipps`, then settle through the shared payment service.
Google conversion delivery follows the paid-order event. Dintero checkout, webhook verification
and the optional staging-only Solidus kernel are documented with the engine.

## Seeding

Development/test `db:seed` first builds a per-city baseline for every entry in
`Brgen::DomainRegistry::ENTRIES` after the replant wipe. Each city receives its own
admin, users, communities and posts. A curated `CityContent` bank is used when one
exists; other cities fall back to locale-appropriate names and city-named
`PlausibleContent` copy. Non-Bergen Norwegian cities use the neutral `lokalt`
community rather than a Bergen-branded one.

The remaining bulk vertical catalogue is deliberately Bergen-specific: its
addresses, coordinates, dating bios and local fixture copy belong to
`brgen.no`, which the seed now requires explicitly. The curated
`BergenDemoSeeder` remains a separate disclosed-demo path. Rich synthetic data
belongs in development/test or an explicitly disclosed demonstration deployment;
it must not imply a genuine public audience.

In production-like environments, `db:seed` skips synthetic content by default. An explicit demo
seed requires both `BRGEN_DEMO_MODE=1` and `BRGEN_DEMO_NOTICE=1`; the application shows a
persistent, translated site-wide disclosure while both flags remain set. Keep these settings off
the public production service unless the whole deployment is intentionally a disclosed demo.
`brgen:demo_seed` uses the same guard. In development/test, set
`SKIP_BERGEN_DEMO=1` to omit the curated Bergen fixtures while retaining the bulk fixtures.

`bin/rails brgen:demo_audit` reports likely historical seed identities and linked content without
deleting anything. Review the candidates manually before changing existing records: username
and email patterns are clues, not proof. Seed runs no longer invent listing view counts or
playlist play counts.

The image catalog attaches tracked local media and explicitly credited remote sources. Unprocessed
images selected by the curated Bergen seeder pass through `Shared::PostproProcessor` at seed
time. Rows marked `graded: true` are not processed twice. The `random` preset selector is
deterministic per seed key, so repeated seed runs produce repeatable grading.

Do not scrape or bulk-download Unsplash to populate Brgen. Unsplash's license excludes compiling
images to replicate a similar or competing service, and its API requires hotlinking plus attribution.
Brgen is a social platform, so use generated assets, appropriately licensed local photography, or
sources whose licenses permit the particular use. Keep source and photographer credits in the
catalog whenever supplied.

Users in each city get names in that city's
language through Brgen::CityContent.with_faker_locale. Setting Faker::Config.locale alone gives
English, because Faker's data is tagged nb-NO while the app declares only bare locales. The
photographs the seeds attach are described in config/demo_media/README.md.

## Affiliate income

AffiliateProduct is the stored inventory, and the deals sidebar reads that table and does not
call out on every render. TradeDoubler import needs TRADEDOUBLER_TOKEN, which is issued only
after brgen.no is an approved publisher and each advertiser programme has accepted it, so until
then affiliate:import does nothing. affiliate:health reports counts, staleness and token status.
affiliate:seed_placeholders and affiliate:drop_placeholders work offline. A placeholder row
carries placeholder: true, is excluded from the real scope, is labelled in the interface, and is
never payable inventory. To let TradeDoubler verify ownership, the footer shows
TRADEDOUBLER_SITE_ID and SITE_CONTACT_EMAIL when they are set, whether or not the token exists.

Amazon works in two stages. Each storefront needs its own Associates tag, set in
AMAZON_ASSOCIATE_TAG_SE, _NL and _FR, and a tag from one storefront earns nothing on another's
link, so there is no global fallback. AMAZON_MARKET names the default storefront, and Norway,
which has no amazon.no, maps to Germany unless SE is chosen. With tags alone,
affiliate:amazon_seed writes rows for ASINs the operator picks, and they reach the sidebar
through the same Affiliate.deals path as TradeDoubler. The Creators API catalogue import waits
on AMAZON_CREATORS_CLIENT_ID and AMAZON_CREATORS_CLIENT_SECRET, which Amazon issues after ten
qualifying sales in thirty days. affiliate:amazon_status shows what is configured.

Google conversions travel server to server. GoogleEnhancedConversions posts to the Data Manager
API, the supported path since new adopters of the older upload service were blocked in June
2026. It runs only when GOOGLE_ENHANCED_CONVERSIONS=1 and the Ads customer and conversion-action
ids are set. Email and phone are hashed with SHA-256 and never sent raw, the order id is the
dedupe key, and unpaid orders are never uploaded. Consent is sent only when the answer is known,
and never assumed granted.

## Monetisation

Revenue follows paths the code already serves. The marketplace settles orders through Stripe,
Vipps and Dintero (`Marketplace::Order` payment providers), and payment webhooks enter at
`/webhooks/stripe` and `/webhooks/vipps` on the host. No platform fee is wired: `price_cents`
on an order is the price buyer and seller agreed, so an order today earns the network nothing.
A take rate is a schema change, a product decision and a legal text, and it waits for all
three.

The plan that exists is `brgen_business_presence` in `RAILS/__shared/config/plans.yml`: NOK 399
a month for a local business presence, gated by the `featured_listings` entitlement in the
marketplace listings controller. The `/billing` page shows a plan whose Stripe price env is
unset as not yet available, never as an offer nobody can complete.

Affiliate income ships behind approvals: TradeDoubler needs publisher and programme approval
before `TRADEDOUBLER_TOKEN` exists, Amazon needs a per-storefront Associates tag, and the
Creators API waits on ten qualifying sales in thirty days. Until then, placeholder rows stay
labelled and unpaid. Radio and TV take support only with disclosure.

Rejected as planning fiction: global ad scale before local density, an AI premium before a
daily habit, and paid demand in forty-three cities before one city holds retention. Seed data
is not an audience.

## SEO and growth

brgen wins on place. Each live apex serves unique local URLs — feed, events, marketplace
listings and public community pages — so the honest keyword inventory is city plus vertical:
"bergen markedsplass", "oshlo dating". Growth comes from being crawled correctly and being
worth citing locally, not from doorway pages.

The mechanics the tree carries: `Shared::SitemapBuilder` and the sitemapable concern emit
per-host sitemaps; `Shared::SeoKit` renders titles, descriptions and social card meta;
`/merchant-feed.xml` gives price engines a public, priced and photographed feed with affiliate
rows excluded; structured events ride on the shared engine. nb and en ship as real
translations, and a city without a translation serves one honest language.

The rules: public value before login walls where privacy allows; show only apexes that are
both in the network set and live in `LIVE_DOMAINS`, and say "eleven members, seven live"
instead of "live in forty-three cities"; disclose affiliate relationships on every hop; upload
conversions only for paid orders, consent sent when known and never assumed; measure through
`Shared::GrowthReport` — visits by host, outbound clicks, paid orders — and let that evidence
decide where the next city opens.

## IRC bridge

The gateway is a limited channel bridge, not a general IRC server. It supports
registration (`NICK`/`USER`), `PING`/`PONG`, `JOIN`, `PART`,
channel `PRIVMSG`, `NAMES` and `QUIT`. Unknown channels return 403.
`NAMES` displays the read-only role prefixes supplied by Brgen's roster;
clients cannot change them because `MODE` is not implemented. `CAP` is
ignored: no capabilities are negotiated. Direct messages, NickServ and SASL
are not supported. The focused tests cover this subset, not the full IRC
protocol.

The socket server polls web-side messages every two seconds and relays them to
joined IRC clients. It binds to `127.0.0.1:6667` by default and starts only
when `bin/irc-gateway` is invoked. To expose it, the operator enables
`irc_gateway` in `rc.conf.local` using `OPENBSD/mirror/etc/rc.d/irc_gateway`,
then either terminates TLS on 6697 in relayd and forwards to the local port,
or opens 6667 in pf with `IRC_HOST` set (cleartext). DNS for
`irc.brgen.no` is a separate step.

Web viewers see IRC posters as anonymous handles while the IRC-side nick is
retained. Direct messages are not bridged, and each bridged nick leaves a user
row that still needs the same review/pruning discipline as guest identities.
## Account deletion and private messages

Account deletion has a 30-day grace period and is processed by the daily
`UserPurgeJob`. Private profile, identity, social-relationship and notification
records are removed; personal location fields are cleared from retained public
content. Messenger preserves message rows so replies and thread ordering do not
break, but messages authored by the erased account are unsent: text is cleared,
attachments are purged, the erased sender's conversation memberships are removed, and
message-targeted receipts, notifications, activity, reactions, votes and outbound-attribution
rows are removed. The sender's identity and associated activity references are removed as well. The regression tests in
`test/jobs/user_purge_job_test.rb` cover erasure behavior; runtime execution is
required before treating the full erasure path as verified.

## Bringing it up

```zsh
MASTER/bin/operator triangle up brgen
curl -fsS http://127.0.0.1:38182/up
doas zsh RAILS/brgen/brgen.sh
cd RAILS/brgen && bin/rails test
```
