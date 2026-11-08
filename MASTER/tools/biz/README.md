# biz — seven concepts, one pair each

Restored from the pub, pub2 and pub3 archives into the pub5 anlage and completed
for Innovasjon Norge applications. Each concept is delivered as one self-contained
HTML document and one PDF printed from it. The separate `__templates/` directory
preserves the original `bob` and `bob2` correspondence in HTML and PDF form; those
files are historical source material, not part of the seven plan deliverables:

    syre/syre.html + syre.pdf                     3D-printede sko, NOK 250 000
    ragnhild/ragnhild.html + ragnhild.pdf         begravelsesbyrå (karaokekiste), NOK 150 000
    speis/speis.html + speis.pdf                  maritime og forsvar, NOK 500 000
    nato/nato.html + nato.pdf                     arktiske dominanseskip, NOK 500 000
    norwegianhedge/norwegianhedge.html + .pdf     Ruby-handelsroboter, NOK 300 000
    pubhealthcare/pubhealthcare.html + .pdf       autonome parametriske sykehus, NOK 500 000
    govt_bergen/govt_bergen.html + .pdf           bergensk selvstyre-teknologi, NOK 200 000

Every plan lives in its own folder named after its html and pdf pair (Johann,
2026-11-07), one pair per folder, and the folder carries **only what the reader
receives**: the html, its svg mark (where one exists) and the pdf. Editable
sources sit beside the folders, never inside one — the seven restored base
documents and all tooling live in `scripts/` — and the published pair is
regenerated from them. The **fetat** plan (Familieetaten) has the same layout:
`fetat/fetat.html + fetat.pdf + fetat.svg` published, its proposal, build,
trace and laws scripts in `scripts/` under the `fetat_` prefix.

Seven concepts, sought funding in total: **NOK 2 400 000**. (ai3 remains in the
pub3/pub5 archives but is not in the keep-list for this restoration.)

## The typographic contract

Johann, 2026-11-07: "all business plans must use bob2.html as starter
template". bob2's token vocabulary is the starter of every plan: the
--color-* tokens, body in **Source Serif 4** and headings in **EB Garamond**
(both variable faces from the Google Fonts link, exactly as on fetat), the
66-character measure on one 1.5 baseline grid, guillemets and true dashes,
sentence-case titles, and a white ground. A plan's own brand mark stays
artwork (syre's fractal, the SPEIS/NORWEGIAN HEDGE gradients, ragnhild's
Nosifer wordmark - the one face still embedded - and govt_bergen's plain
EB Garamond mark). The colophon of every plan names these facts; the old
claim of an embedded EB Garamond, oldstyle prose figures and a #F7F2E9
paper is gone with the archive skin.

The plans are written in Norwegian for Innovasjon Norge applications:
sammendrag, markedsanalyse, teknologi og innovasjon, forretningsmodell,
utviklingsveikart, finansieringsbehov, team og kompetanse, bærekraft og
samfunnsansvar.

The hefte print contract is the one fetat already carries: 156 × 234 mm,
folio in the 12 mm foot, 6 mm head, @page :first with a zero top margin so
the cover is the page, and break hygiene. The PDF is printed from the built
HTML by bp_print.mjs, whose pdfinfo check verifies page size every run, so
the pair cannot drift.

## What the completion added (November 2026)

To satisfy Innovasjon Norge's assessment criteria — innovasjon, marked,
gjennomføringsevne, vekstpotensial og behovet for støtte, plus their
oppstartstilskudd checklist (problemforståelse, løsning og usikkerhet, dagens
alternativ, segment og marked, IPR, team og gjennomføring) — every plan gained
seven new blocks inside the existing eight sections, with all figures derived
from each plan's own data:

- **Hvorfor nå** (sammendrag) — the timing argument.
- **Kundeinnsikt og problemforståelse** and **Markedsføring og salg**
  (markedsanalyse) — evidence from each plan's own pilots, and the go-to-market.
- **MASTER-adaptasjon og plattformforslag** (teknologi) — see below.
- **Enhetsøkonomi** (forretningsmodell) — per-unit economics table.
- **Milepæler og måltall** (utviklingsveikart) — milestone table.
- **Resultatbudsjett, Likviditetsbudsjett og Risiko** (finansieringsbehov) —
  three-year budgets and a risk matrix; the existing budget allocation doubles
  as the investeringsbudsjett.
- **Behov for ekstern kompetanse** (team) — what is bought in, and why.

All budget arithmetic is machine-verified (rows sum, cash balances carry
forward). Oldstyle figures stay in prose, tabular figures stay in tables.

## Platform proposals and MASTER adaptation

Per the restoration brief:

- **govt_bergen** carries three governance proposals on the same stack
  (OpenBSD, Ruby, pub5 MASTER law-catalogue governance):
  *FETAT — ny barnevernsforvaltning* (the FETAT/Familieetaten proposal, the new
  Norwegian Barnevern, working master at
  `MASTER/tools/biz/fetat_proposal.md`, published as its own plan folder
  `fetat/fetat.html + fetat.svg + fetat.pdf` in the hefte format
  156 × 234 mm: evidence-based decisions, 48-hour first
  response, multidisciplinary teams, regional units, child hotline 123,
  independent review — now with the hefte's own facts: 24 EMD judgments under
  ECHR art. 8, NOK 26 bn annual cost across 356 kommuner, the 3 % vs 35 %
  appeal-approval contrast between Trøndelag and Oslo, NOU 2023:7, the four
  pillars, the 30 %/50 %/0/400 mill effect targets and the
  pilot-2026/validation-2027/scale-2028–30 phases, contact fetat.no),
  *politietaten under loven* (a police-integrity platform motivated by the
  «Byen vest for loven» findings: cryptographic chain-of-custody for evidence,
  protected complaint and whistleblower lines, open per-station statistics, AI
  pattern-flagging for human review only), and *parametrisk arkitektur og
  Bergen-coin* (adaptive municipal buildings, a local cryptocurrency under the
  same open-source transparency rules, smart contracts and the transparent
  open-source budget).

  The party movement behind the plan is imported from the Evighetspartiet
  document: motto «Frihet, autonomi, transparens», the five core values, the
  political landscape measurements (60/45/70/80), the five-point political
  platform (selvstyre, direkte demokrati, karbonnøytral 2030, boliger,
  næringsliv), the three movement phases (mobilisering, valgkamp,
  implementering — lokalvalget 2027 as the full-scale pilot) and the movement
  financing target of NOK 10 million (donations 4, crowdfunding 3, membership
  2, events 1 — sum machine-verified), kept strictly separate from the
  company budgets.
- **pubhealthcare** now states the national health platform behind the
  hospitals: hAPI on OpenBSD (the RFC-draft successor to FHIR from the pub
  archive), SSHM for molecular-scale patient modelling, the druglab
  synthesizing cube with Laupsa Pharmaceuticals, governed by MASTER's
  law-catalogue so no algorithmic decision touches a patient record without a
  human, documented, reviewable decision.
- **syre** (and by the SYRE technology-sharing, **speis**) now describe the
  adaptation of pub5's MASTER to the 3D-printer farm — every print job is a
  proposal admitted by the written law catalogue, scanner logs as evidence in
  the QA system — and the materials-science program that screens graphene-TPU,
  mycelium and self-healing polymer compounds against one test protocol and
  locks the winning compound into the law catalogue as production law.

## Ragnhild: archive material imported (November 2026)

The tjenestesider, the Ilumild booking page and the halloween versions from
the operator's archive are now woven into the plan:

- **Tjenestekatalog og partnere** — the full catalogue (Karaokekiste,
  Diskokiste, klovne-pallbærere, pyroteknisk avskjed, stand-up-eulogier,
  poetisk avskjed, sprø kistedesign, kiste med rutsjebane, romferd, musikalsk
  avskjed, Piratferd i flammene) with each service's fixed partner (Festbyrået,
  Lysmestrene, Latterfabrikken, Fyrverkeriekspertene, Humorhuset, Ordsmia,
  Kistegalskapen, Morrogutta).
- **Søstermerket Ilumild** — the quiet sister brand on the same booking
  platform: Basis fra 30 000 / Premium fra 60 000 / Deluxe fra 120 000 kroner
  plus 50/80/200 per guest, the 60-second calculator, Ro-modus, WCAG AA and
  the ≥ 12 % conversion target.
- **Den digitale plattformen** — the two-week MVP pilot and the OpenBSD/Ruby
  stack (Rails, Hotwire/Stimulus, OpenBSD, CRM), GDPR and encryption, offline
  fallback, authorised funeral contractors, green profile.
- **Merkevare og kanal** — the founder story (karaoke exile, ABBA, the
  2-million-follower begravelses-influencer, #EtterLivMålene), the signature
  «Vi tar vare på deg, selv når du ikke lenger tar vare på deg selv», and
  halloween as the annual campaign arena.

## Ragnhild: separate artist-grant guide

`BIZ/ragnhild/ragnhild_legater.html` is a separate five-page guide to exhibition
project support and artist grants. It is not part of the funeral-services
business plan in `ragnhild.html`. The guide was restored from
`pub4/BPLANS/ragnhild_legater.html` and its funding routes were rechecked on
8 November 2026. The archived BKV dates for 2027 were not retained: NBK's
public schedule still showed 2026 project-support rounds, with no confirmed
2027 dates. Bergen's professional-art funding deadlines and the Fegerstens
foundation's eligibility and biennial cycle were checked against their
current source pages.

The pub4 archive had no matching PDF. Treat the restored HTML as recovered
source material, not a completed print pair, until a PDF is rendered and its
page breaks and text are visually inspected.

## Logos restored

If the original HTML carried a custom logo, it is restored as a static mark on
the opening page, with its provenance noted in the colophon:

- **syre** — the «SYRE» fractal mark (Flower of Life pattern-fill wordmark,
  SVG with displacement and glow filters) from the pub generation, static.
- **speis** — «SPEIS» gradient wordmark, pub2 generation
  (#ff007f – #00c9ff – #ffcc00), static.
- **norwegianhedge** — «NORWEGIAN HEDGE» gradient wordmark, pub2 generation,
  static.
- **govt_bergen** — «Bergens Selvstyreparti» set plain in the anlage's own
  EB Garamond at the customer's request (November 2026, «use plain, same font
  as the rest for now»); the pub2 gradient wordmark
  (#ff8c00 – #ff0080 – #8a2be2) was withdrawn, and the colophon records the
  replacement.
- **ragnhild** — «Ragnhilds» wordmark set in Nosifer (SIL Open Font License),
  the dripping face from the archive's halloween versions, restored at the
  operator's request. Nosifer carries the wordmark only; every semantic
  heading stays in EB Garamond, per the visual-identity contract in
  MASTER's laws (brand marks are artwork, wordmark typography never replaces
  semantic page headings).
- nato, pubhealthcare — no custom logo exists in any archived
  generation; nothing was added.

The gradients are kept at reduced size and static (no animation) so the marks
sit quietly in the Bringhurst anlage; the original CSS animations live on in
the pub2 archive.

## Build pipeline (law-compliant)

MASTER/data/laws.yml governs this tree. The committed build and check
pipeline is plain Node.js and Ruby: it reads and writes files directly and
does not invoke Python, Bash, sed, awk or shell text processing.

The sources of record all live beside this file, in `MASTER/tools/biz/`: the
seven restored base documents (`<plan>.html`), the completion content
(`plans_a.mjs`, `plans_b.mjs`, `content_add.mjs`), and the FETAT working
material (`fetat_proposal.md`, `fetat_build.rb`, `fetat_trace.rb`).
`convert_content.mjs` is an optional one-time re-importer for the archived
text sources; run it only when those two original files are available,
setting `BIZ_LEGACY_SOURCE_DIR` to their directory.

The standing build sequence regenerates every published folder from sources:

    BIZ_OUT_DIR=/tmp/pub5-good-BIZ node bp_build.mjs      # build the seven from sources
    BIZ_OUT_DIR=/tmp/pub5-good-BIZ node bp_retemplate.mjs # re-skin onto the bob2 starter
    BIZ_OUT_DIR=/tmp/pub5-good-BIZ node bp_check.mjs      # independent verification of the outputs
    BIZ_OUT_DIR=/tmp/pub5-good-BIZ node bp_print.mjs   # print PDFs via Chromium
    BIZ_OUT_DIR=/tmp/pub5-good-BIZ node bp_index.mjs   # regenerate index.html
    ruby fetat_build.rb && node bp_print.mjs           # fetat: build, then print its pdf

The plan folders are judged by the one Law system, not by a BIZ-local
assessor: `MASTER/data/laws.yml` owns every Law identity and `MASTER/law/`
implements the detectors, including `BUSPLAN_*`, `PRINT_PAGE_CANON` and
`PRINT_FOLIO_PRESENCE`. Run `bin/check --profile=agent` for the whole
repository, which is also the only supported way to audit these plans.

and the published trio is copied from the output directory into the plan
folders (the folders carry only the trio: html, svg mark where one exists,
pdf). `bp_check.mjs` output must be read with the same `BIZ_OUT_DIR` as the
build, or it verifies stale files.

Source defaults to this BIZ directory. Set `BIZ_SOURCE_DIR` when using a
separate clean source tree. Generated files go to the system temporary directory
(`pub5-good-BIZ`); set `BIZ_OUT_DIR` to choose another destination.
The PDF step discovers Chrome/Chromium on the host; set `BIZ_CHROME_BIN`
when it is not on PATH. `pdfinfo` (Poppler) is also required and can be
selected with `PDFINFO_BIN`.

bp_check.mjs executes the HTML/typography/prose laws (lang, charset, single
h1, heading hierarchy, final newline, tabs, trailing whitespace, blank-line
runs, TODO/placeholder scan, ASCII line art, trailing arrows, Norwegian
leech words, character audit, and the full budget arithmetic re-read from the
output files — inconclusive checks fail loudly, never pass silently).
