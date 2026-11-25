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

**Vertical product briefs:** [Dating](#brgen-dating) ·
[Marketplace](#brgen-marketplace) ·
[Takeaway / food](#brgen-takeaway) ·
[Radio](#brgen-playlist) ·
[TV](#brgen-tv) ·
[Maps](#brgen-maps) ·
[Messenger](#brgen-messenger).

These briefs preserve the distinct product promises while treating the active engine,
routes and tests as the authority for what is actually available.
## Marketplace integration

The Marketplace engine owns listings, stores, orders and its storefront; the Brgen host owns
city identity and the webhook entry points shared with the other verticals. The host has no
listing model. The engine's product and feature status lives in
[the Marketplace section](#brgen-marketplace) and `RAILS/apps.yml`.

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
photographs the seeds attach are described in the [Demo media section](#demo-media).

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

## Full production redeployment prompt

Use the following instruction with MASTER from the operator workstation when preparing to
restore the production network. It defines the intended full redeployment; it does not waive
any admission gate.

Restore the pub5 production network on vm23 from one exact, reviewed commit on
`origin/main`. The deployment scope is the tracked OpenBSD host mirror and every active
production target in `OPENBSD/deploy_inventory.json`, generated from `RAILS/apps.yml`,
including the MASTER web application. Do not invent targets from DNS records, old scripts,
or historical notes. The canonical host is vm23 and its repository checkout is
`/home/dev/pub5`.

Work from the root of a clean workstation checkout. Read the complete current
`OPENBSD/RUNBOOK.md`, `OPENBSD/data/operator.yml`, `OPENBSD/README.md`,
`MASTER/README.md`, `RAILS/apps.yml`, `OPENBSD/deploy_inventory.json`, and the
relevant deployment source, tests and recovery instructions. Resolve conflicts between
implementation, tests, safety checks, runbooks and operator recipes before touching the host.
For every OpenBSD-native command, service action or configuration interface, establish vm23's
exact OpenBSD release and architecture and complete the runbook's target-version manual-page
preflight. Do not substitute remembered behavior or current manuals for the target release.

Begin with read-only inspection. Confirm that the workstation is on `main`, the working tree
is clean, and local `HEAD` exactly equals the fetched `origin/main` SHA. Record that SHA.
Verify vm23 identity, release, architecture, repository path, available disk and memory,
current service state, existing deployment sessions and unresolved recovery receipts. Compare
the host checkout and deployed app revisions with the pinned source. Inspect the intended
service, filesystem, doas and ownership boundaries. Do not print secrets or copy credentials
into logs.

Run the complete local deployment admission checks, including the deploy rehearsal, OpenBSD
configuration and safety checks, relevant MASTER boot/law checks, and the required Rails
source and application test suites. Review every failure; a skipped, timed-out, inconclusive
or unexecuted check is not a pass. Confirm that the deployment inventory, host mirror,
installed configuration expectations and recovery path agree. Do not use break-glass
environment variables or flags to turn a failed check into a pass.

**Privilege boundary to verify before deployment:** the repository uses one
brokerless deployment architecture: native `rcctl` service control, the fixed
app-user helpers under `/usr/local/libexec/`, and durable receipts written by
`OPENBSD/lib/deploy_records.rb`. The retired `pub5-admin` program and manual
page are not tracked. Before deploying, trace the deployer, helpers, doas
policy, mirror, tests, safety checks, recovery paths and operator instructions
and confirm they agree. If any broker reference, stale test or contradictory
instruction remains, stop and report `BLOCKED`; do not restore the broker,
bypass a check, weaken a gate or widen privilege to make it pass. Correct the
inconsistency in the owning source, re-run the focused contracts and all
admission checks, and deploy only when they pass together.

Check domain ownership, DNS delegation, NSD zones, relayd routes, certificate SANs and public
HTTPS independently. A city catalogue entry, DNS zone, certificate or relayd keypair is not
proof that a hostname is publicly live. Deploy only hostnames with verified ownership and
an approved service route. Preserve pending, parked, stale and unverified domains; do not
publish them as restored. Do not make speculative registrar, DNS, firewall or certificate
changes as part of an application deployment.

When—and only when—every preflight item is `PASS`, execute the full deployment from the
workstation repository root with this one canonical command:

`MASTER/bin/operator vps deploy all --remote`

This is the operator entrypoint. It performs the workstation preflight, pins the proven SHA,
starts the serial deployment through the vm23 tmux session, applies the tracked host mirror
and deploys the registered applications, including MASTER/web. Let its normal wait and
post-deployment checks finish. Do not substitute a direct SSH command, invoke
`OPENBSD/bin/vps-deploy` by hand, call individual app deploy scripts, run a separate mirror
apply, or start parallel app deployments. Do not run `/fix` on vm23.

After completion, capture the exact deployed SHA and the full deployment receipt. Verify
`MASTER/bin/operator vps state`, the remote service and public route canaries, and
`OPENBSD/bin/domain_watch.rb --tls`. Check each registered app and each intended public
hostname separately. Report which services answer, which routes pass, which domains have
verified DNS/TLS/HTTPS, and which remain offline or pending. A successful command launch,
a tmux session, a successful mirror apply, or a certificate alone is not deployment success.

**Stop and report immediately** if the checkout is dirty or divergent; the host identity or
manual evidence is incomplete; any test, safety check or canary fails or cannot run; the
privilege model is inconsistent; the host has insufficient resources; a deployment session
or recovery receipt is unresolved; the pinned SHA differs at any stage; or DNS, TLS, service
ownership or rollback state is uncertain. State the exact failed check, command, exit status,
host and SHA, observed evidence, and the next safe read-only diagnostic. Do not retry
automatically, skip tests, weaken a gate, change unrelated host configuration, or claim
success. Recovery and rollback are deliberate, separately reviewed operations.



## Vertical and demo-media guides

Brgen is one application with several mounted engines, not a fleet of separately deployed apps. Their product notes and implementation contracts are collected here; the engine directories remain the code owners.


### Demo media

**A city network should look lived in on its first night, so the Bergen seeds carry photographs
made for them, and the app keeps those photographs inside its own tree.** A seed run on the
production box finds its pictures on disk instead of asking the internet for them.

The catalogue is bergen.yml. It maps each seed key to a picture and holds sixty-nine rows.
Sixty-four of them name a file in the images folder beside it, and each of those is marked
graded, because the frame has already been through postpro once and a second pass would stack a
second grain field on the first. The other five are Wikimedia Commons photographs of Bergen with
their credits written beside them, and those five are fetched over the network when the seed
runs.

Shared::DemoMedia looks a key up here first. A key the catalogue does not hold falls back to a
picsum landscape when the seed asks for a remote image, and to no picture at all when the seed
asks for the catalogue alone, as the bulk seeds do. A row whose file is missing is skipped with
a warning rather than raised, since one failed seed blocks every deploy. Setting SKIP_DEMO_MEDIA
turns attachment off, and the test environment never attaches. DEMO_MEDIA_CATALOG points the
lookup at a different catalogue, and DEMO_MEDIA_CITY at a different city's file.

The frames are prompts in STUDIO/lora/seed_media.yml, rendered on Replicate by
run_seed_media_replicate.rb in STUDIO/lora/_toolkit and filed here by
install_seed_media.rb. That script grades each frame at the preset its prompt names, never
overwrites a frame already filed, and caps the long edge at 1280 pixels. The four dating
portraits are general-model strangers, every one an adult, with no likeness of anyone real. The
prompt, model, seed, prediction and postpro preset of every render are recorded in
STUDIO/lora/seed_media_manifest.yml.

These graded copies are tracked in git, which is a deliberate exception to the rule against
committing generated assets. That rule keeps build output and renders out of history because
they can be made again from source. These cannot: a render costs money and never comes out the
same twice, and the deploy copies only tracked files to the box, where the seeds read them. So
the app keeps the small copy, and the full renders and their ungraded originals stay out of git
on the machine that made them.

Unprocessed sources receive one Postpro pass during the curated seed run. `preset: "random"`
chooses a valid preset deterministically from the seed key; repeating the seed does not change the
grade because the random number generator changed. A row marked `graded: true` is already
processed and must not receive a second pass.

For each new locally supplied image, record its source URL, source name, photographer,
photographer URL, license and/or required credit in the catalogue. Those details are copied to the
Active Storage blob metadata, and post cards/post pages can display a credit when one exists.
Do not bulk scrape Unsplash: its license excludes compiling its images to reproduce a similar or
competing service. Use the existing generated frames, the credited Wikimedia Commons sources, or
another source whose license permits the specific intended use.


### brgen dating

**Matchmaking for a city you already live in.** Dating shows you the people of your own town,
asks them to prove they are who they look like, and leaves the rest to the two of you.

Dating is mounted at `dating.<city>`, for example `dating.brgen.no` and
`dating.lsangeles.com`. It runs inside Brgen's Rails process and uses Brgen's
users. The city is resolved from the apex host; Dating is not a separate app.

The Brgen host map appears above; `AGENTS.md` carries the agent-specific constraints.

Each person builds a profile of photos, a short bio and up to three prompt answers. The deck
shows one candidate at a time, and the next one comes from `home#next`. A like or a dislike
moves the deck along, and a rewind undoes the last dislike. When two people like each other the
engine creates a match, and the matches page lists them. A separate page shows who has liked
you, since that is a different decision from swiping through the deck. A short list of picks,
five a day, gives a break from a deck with no bottom. The list is stored, so it stays the same
all day, and it skips anyone who was picked earlier in the week.

Two things stand between a stranger and a face in the deck. Making or editing a profile asks
for Vipps Login first, because a verified phone number puts a real person behind a profile.
Beyond that, a person can ask for a verification: a selfie in a pose the app draws at random,
reviewed by a human. Face matching is not automatic, since it fails on the people it should
serve, and a wrong rejection on a dating profile is worse than a slow approval. Only a
reviewer, the same admin who works the moderation queue, may approve or reject one.

The Vipps check fails closed. With `VIPPS_CLIENT_ID` and its secret in `/etc/brgen.env`, only a
Vipps-verified account can put a profile in the deck. Without the keys the writing surfaces lock:
the old behaviour treated a missing variable as an open door, which is the wrong default for a
dating product. A server that deliberately runs without Vipps keys (a demo, a fixture city) opens
the gate only when the operator sets `DATING_IDENTITY_BYPASS=demo` in the same env file — a named
decision, visible next to the variables it stands in for.

The models are `Profile`, `Prompt`, `Like`, `Dislike`, `Match`, `DailyPick` and `Verification`.
`isolate_namespace Dating` gives their tables the `dating_` prefix. The engine lives in
brgen's database and carries no migrations of its own; they are in `RAILS/brgen/db/migrate`.
Routes are drawn on `Dating::Engine`, and brgen mounts the engine at the root under
`constraints(subdomain: DATING_SUBDOMAINS)`. From the host, reach its helpers namespaced, as
in `dating.matches_url(…, subdomain: "dating")`.

## Visual direction

**Tinder and happn are interaction references, not product authorities.** Keep discovery focused
on one substantial profile at a time, with fluent swipe and tap controls, legible photographs,
short prompts and a clear route from mutual match to conversation. Make local discovery and
path-crossing context understandable without exposing a person's precise route or current
location. The profile must remain more than a photograph: preserve prompts, biography, intent
and verification context.

Do not add streaks, artificial scarcity, opaque ranking, paid visibility or interaction
patterns that pressure a person to like or disclose more than they choose. Reporting, blocking,
privacy and identity checks must remain easy to find.

## Original product promise and present boundary

The archived brief described a safe, local way to meet people: profiles, preference-aware
discovery, geographic controls, mutual matches, conversation and member-controlled privacy.
The current engine delivers city/radius discovery, profile photos and prompts, like/dislike and
rewind flows, mutual matches, a held daily pick, a message hand-off, and a human-reviewed
verification request. Vipps identity gating fails closed when configured; an unconfigured
production server does not silently admit unverified profile publishing.

Brgen's shared events surface remains the place for city events. A dedicated dating-event planner,
paid boosts, premium membership and super-likes are not presented as live Dating features. The
old brief's claims of ML-powered compatibility, anonymous browsing modes, online-presence
indicators and automatic facial verification are not current implementation facts. Matching must
remain two-sided and respectful: location is a discovery filter, not a public exact-location
disclosure, and a verification badge means a human-reviewed request was approved.

The engine depends on `pub5-shared` for `User`, authentication, tenancy and the design system,
and its boot shape comes from `Shared::VerticalEngine`. Its strings live in the engine's own
Norwegian and English locale files, and Norwegian is the default.


### brgen maps

**Places and a live map, for whichever city you arrived through.** Maps puts the shops, cafes
and corners of your town on one screen and lets you say that you were there.

Maps is mounted at `maps.<city>`, including `maps.brgen.no` and
`maps.lsangeles.com`. It runs inside Brgen's Rails process, uses Brgen's
users and resolves the city from the apex host. It is not a separate app.

The Brgen host map appears above; `AGENTS.md` carries the agent-specific constraints.

The home page draws the map on a MapLibre canvas, with tiles from OpenFreeMap. Its GeoJSON
source clusters nearby places, events and stories at city scale, expands a cluster on selection,
and draws individual points as GPU map layers at street scale. Search updates that source rather
than rebuilding a DOM marker for every result. Marker and cluster colours resolve from the Maps
surface tokens; the Positron basemap stays deliberately quiet beneath the city data. The places
page remains the complete list/search alternative, with a filter by kind, and answers JSON to the
same query for the map. A place page shows the recent check-ins and the
places nearby. A signed-in visitor, a soft guest included, can check in with a short note.

The engine owns routes, controllers and views only. `Place` and `PlaceCheckIn` stay in brgen's
models, because restaurants and stores point at a place too, so it has more than one consumer
and is shared the way `User` is. Check-ins therefore live in brgen's database, in
`place_check_ins`, with no `maps_` tables. Routes are drawn on `Maps::Engine`, and brgen mounts
the engine at the root under `constraints(subdomain: MAPS_SUBDOMAINS)`.

The map is built in the browser, so the home section carries a `map-morph-guard` Stimulus
controller that keeps it out of a Turbo page morph, the same `turbo:before-morph-element` guard
the shared tiptap editor runs over a mounted editor. The controller lives in the engine's
`app/javascript/controllers`, which brgen pins through the vertical list in its
`config/importmap.rb`; nothing refreshes the page yet, and the guard is in place before one
does. Its first controller tests run inside brgen's suite, under `test/controllers`.


### brgen marketplace

**Every listing in brgen lives here, the shop's product and the chair someone is selling alike.**
Marketplace is one place for a city to buy, sell, rent, hire and order dinner, without asking
anyone to learn a second site for each.

Marketplace is mounted on each city's localised commerce subdomain:
`markedsplass.brgen.no`, `marketplace.lsangeles.com`, `marktplatz` in
Germany and `mercato` in Italy. `Brgen::DomainRegistry::SUBAPP_ALIASES`
maps each spelling to this engine. Marketplace runs inside Brgen's Rails
process and uses Brgen's users; it is not a separate app.

The Brgen host map appears above; `AGENTS.md` carries the agent-specific constraints.

## Restored marketplace intent

The original brief aimed at both local person-to-person exchange and professional shops:
discoverable listings, trustworthy sellers, useful search, direct buyer/seller contact and
location-aware inventory. The current data model deliberately supports both: a listing may have
a store or belong to an individual seller. The current storefront and seeded catalogue are
shop-first, so the presence of an individual-listing model must not be mistaken for a finished
classifieds experience.

Category and full-text search, locality filters, facets, saved searches, wishlist, reviews,
public listing questions, variants, order state, returns and the native seller surface are
implemented. AI recommendations, coupon/referral-credit campaigns, anonymous contact relay,
full shipping-label/rate integrations, catalogue-scale multi-currency operations and the
Solidus storefront remain separate work. Solidus is optional and staging-only; it is not the
public production storefront.

Store owners open a shop and post product listings across categories. Buyers add listings to a
cart, give an address, and check out through Dintero, Vipps or Stripe, whichever is configured.
Sellers take payouts, answer public questions on a listing, offer sizes and colours as variants,
and accept returns. Both sides leave reviews. Deals and saved searches aid discovery, a star
bookmarks a listing for the wishlist page, and a merchant feed in XML goes out for shopping
search engines.

The two tiers are one model rather than two places. `Listing belongs_to :store, optional:
true`: with a store it is a shop's product, and without one it is a person selling a chair. The
seeds always attach a store, there is no separate casual surface, and the storefront chrome
wraps both. A listing also has a kind. Goods is the default, and job, housing and gig listings
carry their own facts in a detail table each, so that no column sits empty for every bicycle.
The kind is a parameter of the index page. Seeded categories are consumer goods only:
electronics, clothing, furniture, vehicles and services, each with children.

Nothing casual lives in the host app, so do not look for it there; the host has no listing
model at all. What is Craigslist-shaped about brgen is the access model. `ListingPolicy` asks
only for a user, and `Shared::Authentication` gives an anonymous visitor a soft `Current.user`
to list with, so no one has to sign up first.

The models are `Store`, `Listing`, `Category`, `Order`, `Checkout`, `Review`, `Deal`,
`ListingFavorite`, `SavedSearch`, `Address`, `Payout`, `Question`, `Return`, `Variant`,
`VariantOption`, `ListingEvent`, `WebhookDelivery` and the three detail tables `JobDetail`,
`HousingDetail` and `GigDetail`. `isolate_namespace Marketplace` gives their tables the
`marketplace_` prefix, and the migrations are in `RAILS/brgen/db/migrate`. Payment services
and the Dintero client are in brgen's `app/services/marketplace/payments`, not in the engine.

Routes are drawn on `Marketplace::Engine`, and brgen mounts the engine at the root under
`constraints(subdomain: MARKETPLACE_SUBDOMAINS)`. From the host, reach the helpers as
`marketplace.listing_url(…, subdomain: "markedsplass")`. The saved list is at `/wishlist`,
because the host declares `/saved` for bookmarks before it mounts this engine, and a `/saved`
here would never run.

Payment callbacks split between engine and host. `webhooks/dintero` and its signed session
callback are engine-local. The `webhooks/stripe` route in the engine hands off to the host's
Stripe controller, so that a dashboard pointed at either URL still pays the order, and the
host also owns `/webhooks/vipps`. Dintero webhooks are verified on the raw body before any
JSON parsing, and each delivery is stored for replay handling.

## Visual direction

**bol.com and Kaufland.de are commerce usability references.** Keep search prominent, category
navigation predictable, filters relevant to the selected category, and the catalogue dense
without making product images or prices hard to scan. Product cards should establish the
product, price, condition, seller and delivery facts in a stable order. Product pages should
make the gallery, variants, availability, seller trust, delivery and buy box easy to compare.

Preserve separate trust cues for professional shops and private sellers; do not imply that one
has the guarantees of the other. Borrow commerce geometry, not another retailer's identity,
copy or campaign assets.

## Food

The canonical food surface is `/food` on the localised Marketplace host, as in
`markedsplass.<city>/food` or `marketplace.<city>/food`. Restaurants, menus, delivery drivers,
group orders and reviews are backed by the nested `Takeaway` engine, kept at
`engines/takeaway`. Marketplace and takeaway share one campaign-art system, described in the
shared engine's README. The former `takeaway.<city>` host remains a compatibility mount of the
same engine, and new links should point to Marketplace.

## Dintero

Dintero owns marketplace money movement. A seller's payout destination must be approved and
ACTIVE before the seller's slice goes out in an inline split. BRGEN stores the exact split
contract on each local order and reuses it for capture and refund, so a later change of
configuration cannot rewrite a historical transaction. Capture is a separate step from
authorisation, and BRGEN does not mark an order paid because a browser came back from checkout.
Paid status follows the webhook.

Dintero's Shopping API creates the payment sessions. The integration keeps its own
`dintero_order_id`, `dintero_session_id` and `dintero_transaction_id` and never treats a local
order id as a Dintero resource. The checkout adapter is gated by `DINTERO_CHECKOUT_ENABLED=1`,
so a credentialed but unverified integration cannot show a payment button before the Shopping
API payload has been exercised in Dintero's test mode. The hook subscription registers against
the HTTPS address in `DINTERO_HOOK_URL`, which must not point at localhost or at Dintero.

## Solidus

Solidus is an optional commerce kernel for catalogue, cart, checkout, fulfilment and merchant
operations. It stays behind `SOLIDUS_MARKETPLACE=1` and mounts at `/solidus` only when its gems
are also loaded. The native `Marketplace::*` models remain the public seller and order domain
until a deliberate cutover. Listings, stores, orders, seller policy, buyer and seller
messaging, local geography, offers, questions and returns stay BRGEN's own. BRGEN does not
install the legacy solidus_marketplace extension.

The 1 GB OpenBSD host is the wrong place to install Solidus. Install it only on a staging host
with a database the Solidus deployment supports. Before any production cutover, verify the
Dintero Shopping payload against the current test account, and exercise authorisation, capture,
refund, duplicate delivery, seller approval and settlement events.


### brgen takeaway

**Good food from kitchens in your city, ordered without leaving the local network.** Takeaway
connects restaurants, their menus, neighbours and delivery drivers. It is the food-ordering
surface inside Brgen Marketplace, not a separate Rails application.

Takeaway is nested inside the Marketplace engine. Its canonical route is
`/food` on the city's localised Marketplace host, such as
`markedsplass.brgen.no/food` or `marketplace.lsangeles.com/food`.
The historical `takeaway.<city>` host remains as a compatibility mount;
new links should use Marketplace. Takeaway is not a separate Rails app.

The Brgen host map appears above; `AGENTS.md` carries the agent-specific constraints.

## Recovered product promise

The original Brgen plan described local restaurant discovery, menus, ordering, order tracking
and delivery coordination. The current Takeaway engine has grown beyond a static restaurant
directory:

- Public restaurant discovery with cuisine filtering, live search, city context and nearby
  restaurants when coordinates are known.
- Restaurant-owned menus, item availability, photos, opening hours, minimum order values,
  delivery fees and stated delivery radii.
- Guest-friendly browsing and ordering without forcing a full account registration first.
- Server-calculated order totals, delivery address and optional tip; client-submitted totals are
  never trusted.
- A guarded order lifecycle: pending, confirmed, preparing, out for delivery, delivered or
  cancelled. Invalid transitions are refused.
- Scheduled orders, immediate-cart expiry, reorder from a previous order and customer-visible
  status notifications.
- Shared group orders: one host opens a token-addressed order, invites others to add their own
  lines, and places the combined ticket.
- Delivery-driver profiles, availability and dispatch relationships; a driver is attached to an
  order only when the dispatch rules have a suitable candidate.
- Restaurant reviews tied to a delivered order, favourites, local discovery and verified
  business status through Brgen's shared verification workflow.
- Activity graph events and shared media processing.

The implementation is backed by the nested engine at
`RAILS/brgen/engines/marketplace/engines/takeaway`, with host-owned migrations and shared Brgen
identity/tenant records. The precise status and implementation notes live in `RAILS/apps.yml`.

## Ordering and delivery boundaries

A restaurant with recorded opening hours is treated as open only when those hours say so.
Scheduled orders may be placed for a future time. When a restaurant has not supplied hours,
the application does not invent a closing schedule.

Delivery-radius checks run only when the restaurant has supplied a radius and both sides have
usable coordinates. A free-text address is not silently geocoded, and missing coordinates are
not replaced with a guessed city-centre pin. Driver dispatch can leave an order unassigned when
there is no verified candidate; the product must not pretend a courier accepted a delivery when
none did.

The current order lifecycle and driver assignment are not a third-party courier network. Live
GPS tracking, route optimisation, external courier APIs, guaranteed delivery ETAs and a
market-wide logistics exchange are separate work until implemented and tested.

## Architecture

Takeaway is nested inside the marketplace engine and mounted by the Brgen host. Its models use the
`Takeaway::` namespace and `takeaway_` table prefix. Migrations are maintained in
`RAILS/brgen/db/migrate`, not in a second independent database.

The engine class includes `Shared::VerticalEngine`. Routes are drawn on
`Takeaway::Engine`; from the Marketplace host the route helpers are namespaced under
`takeaway`. Keep restaurant, menu, order and driver records in the shared city/tenant context.

Marketplace and Takeaway intentionally share the commerce and campaign foundations while
keeping distinct navigation and user journeys. Their nav bars remain separate partials because
their section lists, cart behaviour and route helpers differ.

## Safety and trust

- Restaurant owners may change their own menus and restaurant details.
- Orders remain receipts and are not deleted when a restaurant is archived.
- Buyers can see only their own orders; restaurant owners can see orders for their own kitchen.
- Reviews require a delivered order.
- Order totals are calculated on the server from available menu items.
- Webhook and payment state must come from verified provider events, never a browser return URL.

## Still to build

The archived promise of end-to-end delivery coordination is only partly fulfilled. The next
substantial steps are a tested driver dispatch/acceptance flow, customer-facing delivery status
and ETA semantics, courier location updates with explicit consent, and a provider adapter only
when a real courier partner is selected. Restaurant payout and payment flows must remain
consistent with Marketplace's provider contracts.

Do not revive the old PostgreSQL, Redis, Mapbox, Nginx or Rails 8.0 setup instructions. The
current stack is pinned in `RAILS/apps.yml` and the Brgen host's Gemfile/lockfile.


### brgen messenger

**The city's conversations, without losing the thread.** Messenger is the private and group
conversation surface shared by people using Brgen. It should feel immediate, but its deeper
promise is continuity: a conversation remains readable, searchable, safe to leave, and useful
across devices and time.

Messenger is mounted at `messenger.<city>`, including
`messenger.brgen.no` and `messenger.lsangeles.com`. The Brgen host draws
its routes; the `brgen_messenger` engine supplies the vertical's autoloading
and JavaScript assets. It shares the host app, database, identity system and
deployment. It is not a separate application.

The Brgen host map appears above; `AGENTS.md` carries the agent-specific constraints.

## Recovered product intent

The original Brgen brief promised real-time messaging as part of one integrated city network.
The later architecture adds the features that make messaging dependable rather than merely
instant: durable history, identity and privacy boundaries, moderation, and a clear distinction
between direct messages, group conversations and public rooms.

The current implementation includes:

- Direct conversations reused for the same pair of people, rather than creating a new thread
  every time a different entry point is used.
- Group conversations with membership, an owner/operator role, member invitations and safe
  handover when the last operator leaves.
- Live message delivery through Turbo Streams, with typing indicators and read receipts.
- Message replies, editing within a bounded window, unsending, forwarding and link previews.
- Image attachments and audio voice notes, validated on the server as well as in the composer.
- Search across conversation titles and message bodies, pinned conversations, archive/resurface
  behaviour and cursor-based load-earlier history.
- Per-conversation disappearing-message modes, including view-once semantics, with expiry
  removing content from search, forwarding and previews.
- Story replies that continue in the DM thread after the original story expires.
- Channel rooms, role/mode handling and bot participation; MASTER can be invited to a direct
  or group conversation.
- A responsive desktop layout with a room rail, inbox, thread and contextual artifact pane.

These are code-backed capabilities recorded in the Brgen feature inventory. The authoritative
implementation is in the host models/controllers plus the engine's Stimulus controllers; see
`RAILS/apps.yml` for the precise inventory.

## Privacy and safety

A private message is not a public city post. Conversation membership scopes access to the thread;
blocks are checked in both directions for direct conversations. Attachments are restricted to
supported image and audio media types. Message history is not silently discarded when a sender
deletes an account: the erasure path unsends that person's content and purges attachments while
preserving the thread structure needed by other participants.

Disappearing messages are a user-selected retention mode, not a guarantee against screenshots,
copies or a recipient recording content elsewhere. Voice notes are attachments, not a promise of
end-to-end encrypted calls. The current product does not claim end-to-end encryption.

## What the original brief did not specify

Messenger should eventually make safety controls, notification preferences and account/device
session management easy to understand. Any future encryption, federation, calling or file-sharing
work must begin with a threat model and explicit compatibility decisions; it must not be added as
a cosmetic badge or implied by the word private.

## Architecture

The engine lives at `RAILS/brgen/engines/messenger`. The host owns the shared conversation and message
models because the Brgen feed, dating matches, marketplace listings, stories, channels and
messenger surface all use the same conversation graph. Do not duplicate those models inside the
engine.

`BrgenMessenger::Engine` includes `Shared::VerticalEngine`, which puts the engine's JavaScript
controllers on the asset path. The actual routes are host-drawn under the Messenger subdomain
constraint. Use the host's route helpers and preserve the existing city/tenant scope.

The engine depends on `pub5-shared` for identity, authentication, tenancy, media processing and
shared UI. Read the host's agent notes before changing routes, models or shared concerns.

## Development

Run the Brgen host's test suite for messenger changes; the engine's shared test inventory is
listed in `RAILS/test/engine_roots.rb`. Add regression tests for access control, duplicate direct
threads, group ownership, expiry, unread/read receipts, pagination cursors, attachment types and
Turbo broadcasts whenever those contracts change.

Do not revive the historical PostgreSQL/Redis/ActionCable/StimulusReflex instructions. The active
stack is the one pinned in `RAILS/apps.yml` and the host Gemfile/lockfile.


### Brgen Radio and TV

Brgen's local media surfaces let a city publish and discover sound and moving images without
splitting the community into unrelated networks. Both are mountable engines inside the Brgen
Rails process.

- **Radio** is the public name of the Playlist engine at `radio.<city>`. Its code and models
  retain the `Playlist` namespace.
- **TV** is the video and channel engine at `tv.<city>`.

The city/host topology is defined in the Host and subdomain map above, with
agent-specific constraints in `AGENTS.md`. These engines share Brgen identity, tenancy,
media processing and activity infrastructure.

## Product briefs

- [Radio / Playlist](#brgen-playlist) — local audio publishing, playlists, collaboration,
  hosted tracks, embeddable players, listening parties, timestamped comments and expiry.
- [TV](#brgen-tv) — channels, uploaded video, shows, episodes, subscriptions, watch-time
  discovery, video notes and the live-stream model boundary.

The historical plans also mentioned a record label, creator donations, premium audio tiers,
global music discovery and full live video. Those remain product opportunities, not claims that
the corresponding workflows are already operating. Radio's curated Radio Bergen import has
separate tenant and rights preconditions documented in the [Playlist section](#brgen-playlist).

## Architecture rule

Do not create separate Rails applications for Radio or TV. Their engine code is mounted by Brgen
and their records live in the Brgen database. The active implementation and remaining work are
listed in `RAILS/apps.yml`.


### brgen playlist

**Music is better when someone is listening with you.** Playlist lets a city build its soundtrack
together, hear the same song at the same moment, and talk over it as it plays.

The public host is `radio.<city>`, for example `radio.brgen.no` and
`radio.lsangeles.com`. The source directory, module and tables retain the
name Playlist; the host constraint is `RADIO_SUBDOMAINS`. The former
`playlist.<city>` host no longer resolves, and no alias remains. The engine
runs inside Brgen's process and uses Brgen's users; it is not a separate app.

The Brgen host map appears above; `AGENTS.md` carries the agent-specific constraints.

Users build playlists and sets, add tracks, and invite collaborators as owner, editor or viewer.
Pasting URLs, one to a line, imports tracks into a playlist from YouTube, Spotify, SoundCloud,
Whyp or a direct link, and any member with a real account can upload an audio file as a hosted
track. A set can open a listening party, where people hear the same thing at the same time and
chat beside it. Listeners leave comments pinned to a moment in a track. Likes and listens drive
discovery.

A `DillaSketch` ties a playlist or a set to the studio's dilla engine. Its `render_audio` action
queues `DillaRenderJob` on the bulk queue, which renders through `Shared::DillaProcessor` and the
STUDIO contract, attaches the render to the sketch, and by default publishes it as a track. When
the dilla script is missing on the machine, the sketch records the failure in its `render_error`
instead of failing quietly.

The models are `Playlist`, `Track`, `PlaylistTrack`, `Set`, `SetTrack`, `Collaboration`,
`ListeningParty`, `PartyMessage`, `Listen`, `Like`, `TimestampedComment`, `DillaSketch` and
`AudioVersion`. `isolate_namespace Playlist` gives their tables the `playlist_` prefix, and the
migrations are in `RAILS/brgen/db/migrate`. Inside the engine, write `::Playlist::Playlist` with
the leading colons, because the plain name resolves to the module's own model first.

Routes are drawn on `Playlist::Engine`, and brgen mounts the engine at the root under
`constraints(subdomain: RADIO_SUBDOMAINS)`. Playlists and sets nest their tracks, collaborations
and dilla sketches. A playlist also has an embeddable page and an owner-only analytics page. A
set adds a like and a `listening_party` with its party messages, and `hosted_tracks` and
`listens` round out upload and playback. From the host, reach the helpers as
`playlist.playlist_url(…, subdomain: "radio")`.

The engine depends on `pub5-shared` for `User`, authentication, tenancy and the shared UI. On
screen it uses an immersive stage with a transport bar, and it publishes the bar's height so
floating widgets clear it. Its stylesheet rules live in brgen's single `application.scss`,
scoped under `body.vertical-playlist`.

## Visual direction

**SoundCloud and WHY.IT are creator and discovery references.** Make the creator and the
recording the centre of the product: strong cover art, clear artist identity, useful track rows,
waveform playback, timestamped discussion, playlists, sets and a discoverable creator catalogue.
Human curation and local scenes should sit beside popularity signals, not disappear beneath them.

The Radio Tunnel is Brgen Radio's signature listening mode; it must not become the only way to
browse music. Keep a direct path to tracks, playlists, sets and uploads. Playback begins only
after a reader's gesture, credits and import provenance remain visible, and listening counts
must describe real recorded activity.

## Original creator-platform promise

The archived Whyp.it-inspired brief called for easy local audio publishing, high-quality playback,
embeds, listening insight, privacy/expiry controls and support for independent creators. The
current engine has hosted tracks, external URL imports, playlists and sets, owner/editor/viewer
collaboration, embeddable players, timestamped comments, listening parties, likes/listen records
and per-track expiry. The Radio Bergen archive is a separate curated import and remains gated by
its tenant and recording-rights preconditions.

The first restoration of creator analytics is now in the code: a playlist owner can open an
aggregate dashboard with total listens, listens in the last seven days and per-track counts.
It does not reveal listener identities. This is deliberately a small, privacy-preserving first
step, not a complete creator business suite: unique listeners, retention cohorts, exports,
revenue attribution, donations, paid creator tiers and sponsored-content workflows remain
unimplemented.

The public host is `radio.<city>`; `playlist.<city>` is not a supported host.

## Radio Bergen tunnel and curated archive

The Playlist home now renders the existing Radio Bergen tunnel through the Rails
engine view and Stimulus controller rather than a standalone HTML page. Playback
starts after a user gesture. The legacy opening track is preferred when it exists in the
selected queue; when it is absent, playback starts at the first selected item, preserving
the curated order instead of choosing randomly. Once the selected crate is imported, the
tunnel plays same-origin Active Storage audio and analyses the actual audio signal.

The focused queue-selection regression is available as `cd RAILS && npm run test:radio`.

The exact 35-track selection and ordering live in
`RAILS/brgen/config/radio_bergen/tracks.yml`; filenames map to the archive-root
files in `pub2`, not the stale `mp3/akmd-…` URLs. Audio is deliberately not
committed into Git. The command below is for reference only. Do not execute it
until the tenant-scope blocker is closed and tested locally. Distribution rights
for every recording must also be confirmed.

```sh
RADIO_BERGEN_ARCHIVE_ROOT=/absolute/path/to/pub2 \
RADIO_BERGEN_OWNER_EMAIL=your-existing-account@example.invalid \
RADIO_BERGEN_RIGHTS_CONFIRMED=1 \
bin/rails radio_bergen:import_curated
```

**Tenant guard:** the rake task now resolves the persisted `brgen.no` City and finds the owner inside that tenant. The importer requires that same city and a same-city saved owner, then wraps preflight and writes in `ActsAsTenant.with_tenant(city)`. Missing or cross-city scope is rejected before archive reads or playlist writes. The guard regressions are authored but have not been run in a full Rails checkout; do not import until they pass. Distribution rights for every recording remain a separate operator decision.

The task is intended to preflight all source files, attach them through Active Storage, and
create the playlist in the original order. It is idempotent for matching audio
and refuses to silently overwrite a changed attachment. The confirmation flag
is an operator attestation, not a legal determination.


### brgen tv

**A television channel anyone in the city can start.** Tv gives every neighbourhood a screen of
its own, for what the town makes, what it streams live and what it wants to watch next.

TV is mounted at `tv.<city>`, including `tv.brgen.no` and
`tv.lsangeles.com`. It runs inside Brgen's Rails process, uses Brgen's users
and resolves the city from the apex host. It is not a separate app.

The Brgen host map appears above; `AGENTS.md` carries the agent-specific constraints.

Channels publish uploaded videos and shows with numbered episodes. Viewers comment, take
notes pinned to a moment in a video, and follow channels by subscribing. The data model also
represents broadcasts and live-stream states, but production live-video ingest and delivery are
not available yet: that requires a media server and an external delivery/transcoding tier. The home page is a grid of trending, live and recent videos, ranked by watch
time. The feed at `/feed` is the other shape, one video to a screen, ranked by how much of each
people actually watched, ten at a time. Both depend on `ViewEvent`, which records watch time
because a view counted at page load ranks a bounce like a full watch. Each clip may be built on
a `Sound`, and a sound has a page that gathers every clip made on the same audio.

The models are `Channel`, `Video`, `Broadcast`, `LiveStream`, `Show`, `Episode`, `StreamChat`,
`VideoNote`, `Comment`, `Subscription`, `ViewEvent` and `Sound`. `isolate_namespace Tv` gives
their tables the `tv_` prefix, and the migrations are in `RAILS/brgen/db/migrate`.

Routes live in the engine's own `config/routes.rb`, and brgen mounts the engine at the root
under `constraints(subdomain: TV_SUBDOMAINS)`. Channels are addressed by slug and nest their
videos, live streams and shows. A live stream carries `go_live` and `end_live` and its stream
chats. Stream chat and video notes broadcast over Turbo Streams, on `tv:live_stream:<id>:entries`
and `tv:video:<id>:notes`, with explicit partials rather than inferred ones. Inside the engine
the helpers carry no prefix, so a link reads `channel_url`. From the host, reach them as
`tv.channel_url(…, subdomain: "tv")`.

A new city starts with no television, so the engine ships a content pipeline. The rake task
`tv:starter_pack` writes clips, posters and a manifest. It generates with Replicate when
`REPLICATE_API_TOKEN` is set. Without the token it refuses in plain words, and with
`TV_TEST_CARDS=1` it draws honest test cards with ffmpeg instead. The task `tv:ingest` reads a
manifest into a channel with published videos. It matches channels by slug, so it can run again.

The engine depends on `pub5-shared` for `User`, authentication, tenancy and the design system.
Its models include the shared concerns for media processing, notifications, reactions and
slugs.
