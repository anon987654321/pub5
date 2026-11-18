# BIZ — professional documents, one evidence-backed production chain

BIZ is the professional document studio for business plans, funding applications,
legal instruments, governance and financial reports. Its current portfolio has
seven workstreams:

- **Published:** SYRE, Ragnhild, pub.healthcare, Bergen Selvstyreparti and
  Fremtidens helse-OS. These have reader-facing HTML/PDF pairs.
- **Published guidance:** Ragnhild Mæhle's five-page funding guide lives beside
  her plan. It is preparation material, not a submitted application or a grant
  decision, and is not counted as a sixth business plan.
- **Draft sources:** NORDVAKT Arctic Systems and Norwegian Financial. Their
  editable sources live in `tools/`; no published pair is claimed until build,
  print, arithmetic checks and page-by-page visual review pass.
- **Historical source documents:** SPEIS and Fremtidens NATO-våpen are retained
  as provenance for NORDVAKT. Norwegian Hedge is retained as a historical
  quant-fund concept, not as the active consumer-bank plan.

NORDVAKT combines the maritime and space/Arctic concepts into a civil-first data
and operations platform. It begins with existing, licensed data and software
pilots; it does not assume owned ships, satellites, weapons, NATO procurement or
partner agreements. Norwegian Financial reframes the old quant concept into a
partner-first financial-software and future-bank strategy. Quantitative fund
management remains separate from banking and customer deposits.

The index separates published plans, source-only drafts and archive documents.
Its funding summary reads only the explicit `Innovasjon Norge` row from each
financing table. It does not add total project capital, political fundraising
targets or bank-license capital as if they were grant requests. Funding sources
remain subject to applicant eligibility, scheme rules and evidence.

The portfolio is intended to support applications to Innovasjon Norge and
relevant legater, but no plan is presumed eligible. Verify the applicant,
current call, eligible cost categories, matching funds, state-aid limits and
evidence before submitting. Forecasts and proposed contributions are not
commitments.

## Scope and document profiles

BIZ is a professional document studio, not only a business-plan archive. Its
document families are:

- **Business models and plans:** explore credible alternatives early, test the
  riskiest assumptions, then produce a full plan when the model is supported.
  The published business-plan series uses Bob2. Draft plans remain source-only until their rendered HTML/PDF pairs pass the full release gate.
  Use the nine Business Model Canvas areas as an initial completeness map, not a
  substitute for validation; see the [Innovasjon Norge business-model guidance](https://www.innovasjonnorge.no/artikkel/hvordan-lage-forretningsmodell).
- **Funding applications and proposals:** follow the recipient's current form,
  eligibility, evaluation criteria, attachments, cost rules and evidence
  requirements. Distinguish verified facts, attributed claims, assumptions and
  projections.
- **Legal and contract documents:** identify jurisdiction, governing law,
  parties and capacity; define terms; keep operative clauses internally
  consistent; align dates, term, renewal, termination, payment, delivery,
  intellectual property, confidentiality, data protection, liability,
  indemnities, dispute resolution, schedules and cross-references as relevant.
  Cite authoritative source text and version dates. A qualified lawyer must
  review legal instruments before execution. Automated checks do not establish
  legal validity and these documents are not represented as legal advice.
- **Corporate and governance documents:** board and shareholder resolutions,
  policies, mandates, minutes, institutional strategies and approval records,
  with clear authority, scope, effective date, ownership and version history.
- **Financial and analytical reports:** reconcile every amount to one
  traceable source-of-truth model; state currency, units, periods, assumptions,
  methodology, sensitivity and limitations. Never silently mix actuals,
  estimates and forecasts.

**Layout is profile-specific.** Bob2's 156 x 234 mm hefte format is the
established design for the existing business-plan series only. Do not skin a
contract, board resolution or financial report with Bob2 merely because it is
in BIZ. A4 is the default for legal, corporate and analytical documents unless
the brief or receiving institution requires another format. Each profile sets
its own page grid, measure, type hierarchy, headers, footers, folios, tables,
notes, references and signature/approval zones.

The production bar applies to every page: embedded fonts and correct glyphs;
stable pagination; no clipping or accidental overflow; controlled widows and
orphans; sound table and figure breaks; legible notes; working links and
cross-references; semantic headings, bookmarks, reading order and metadata;
and sufficient contrast and accessible structure. Render every PDF page into
an external audit directory and inspect every page at normal reading size and
print scale. PDF/UA is used when accessibility conformance is required; PDF/A
when archival preservation is required. Neither standard replaces a content
and design review. Rasterizing all pages proves renderability, not human
approval.

No published legal-document family is claimed as complete by this scope
definition. Its jurisdiction, provenance, structural and human-review gates
must be implemented and passed for each actual legal deliverable before it is
released.

## The business-plan typographic contract

Johann, 2026-11-07: "all business plans must use bob2.html as starter
template". bob2's token vocabulary is the starter of every plan: the
--color-* tokens, body in **Source Serif 4** and headings in **EB Garamond**
(both variable faces from the Google Fonts link, exactly as on fetat), the
66-character measure on one 1.5 baseline grid, guillemets and true dashes,
sentence-case titles, and a white ground. A plan's own brand mark stays
artwork (syre's fractal, the historical SPEIS/NORWEGIAN HEDGE gradients, ragnhild's
Nosifer wordmark - the one face still embedded - and govt_bergen's plain
EB Garamond mark). The colophon of every plan names these facts; the old
claim of an embedded EB Garamond, oldstyle prose figures and a #F7F2E9
paper ground belongs to the retired archive generation.

## Visual acceptance points at MASTER, not a second cascade

The cascade architecture is owned once, in MASTER: `MASTER/data/css_architecture.yml`
declares the layer order and the specificity ceiling, and the Laws
CSS_LAYER_STACK, CSS_SPECIFICITY_CEILING, NO_IMPORTANT and
DENSITY_kanso (with its instruments) state the requirements. BIZ accepts
against those Law IDs and ships no layer list, ceiling or autofix of its own. In
practice: no `!important` in any shipped HTML or print stylesheet (a
reduced-motion or print override that must beat the author says
`scan: intentional-important` at the top of its file, the same marker
MASTER's NO_IMPORTANT reads); brand styling reaches the page through the
bob2 token vocabulary, never through selector weight; and where a plan
documents density acceptance, it names DENSITY_kanso, not a private rule.
A BIZ package that grows a Rails app later inherits the RAILS entry pattern
(`MASTER/data/css_architecture.yml` and the existing RAILS entry stylesheets) unchanged.

## The folder law

The folder carries only what the reader receives: the html, its svg mark
(where one exists) and the pdf printed from that html, so the pair cannot
drift. Editable sources and all tooling sit in `tools/`, never inside a
plan folder: active plan sources (`tools/<plan>.html`), with NORDVAKT and Norwegian Financial
authored as complete Bob2 documents and historic SPEIS, NATO and Norwegian Hedge
sources retained as provenance, the build/check/print/index
chain (`bp_build.mjs`, `bp_retemplate.mjs`, `bp_check.mjs`, `bp_print.mjs`,
`bp_index.mjs`), the content modules (`plans_a.mjs`, `plans_b.mjs`,
`content_add.mjs`) and the two new plans' proposals. The published pair is
regenerated from them:

    node BIZ/tools/bp_build.mjs       # bases + additions -> OUTPUT_DIR
    node BIZ/tools/bp_retemplate.mjs  # bob2 skin onto the builds
    node BIZ/tools/bp_check.mjs       # MASTER Law scan + BIZ print/data contract
    BIZ_CHROME_BIN=… node BIZ/tools/bp_print.mjs   # Chromium prints the pdf,
                                      # pdfinfo verifies 442.08 x 663.12 pts
    node BIZ/tools/bp_index.mjs       # this index

`bp_check.mjs` delegates common HTML, prose and hygiene Laws to `MASTER/bin/operator lint` for the business-plan outputs and Ragnhild's funding guide. Business-plan checks remain specific to the Bob2/print contract and independently re-read financial arithmetic; the funding guide has a separate profile check for its five-page structure, accessible calendar headers, cited source links, source-check date and explicit eligibility/deadline caveats. The guide is not passed through the business-plan finance model or Bob2 skin.

`bp_print.mjs` prints with headless Chromium (no Python anywhere in the
chain, per laws.yml REACH_non_native_tool) and checks every page size
against the hefte canon (156mm 234mm); it also verifies the funding guide's five-page output. Raster generation is not visual approval. `bp_index.mjs` fails if a published or archived link lacks its HTML/PDF pair, and lists guidance separately from plans;
it derives the Innovasjon Norge request only from that explicit row in each
plan's financing table and reports source-only drafts separately. The retired
poise/cover generation (bp_cover.mjs) left with its generation; its history
is in git.

RESTORATION_REPORT.md beside this file records how the corpus was restored
and what the archive generations were.
