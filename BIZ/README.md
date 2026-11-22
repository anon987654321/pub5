# BIZ — professional documents, one evidence-backed production chain

BIZ produces business plans, funding applications, legal instruments,
governance documents and financial reports. The index distinguishes published
work, editable drafts and historical sources. Every material claim retains
its source, date, assumptions and uncertainty. Persuasion comes from evidence,
not inflated language. The shared editorial standard lives in
[MASTER/AGENTS.md](../MASTER/AGENTS.md).

- **Published plans:** SYRE, Ragnhild, pub.healthcare, Bergen Selvstyreparti
  and Fremtidens helse-OS. Each has a reader-facing HTML/PDF pair.
- **Published guidance:** Ragnhild Mæhle's five-page funding guide sits beside
  her plan. It prepares the applicant; it is not a submitted application or a
  grant decision, and it is not a sixth business plan.
- **Draft sources:** NORDVAKT Arctic Systems, Norwegian Financial and NEOLIMB.
  Their editable sources live in `tools/`. None has a published pair until
  its build, print, arithmetic checks and page-by-page visual review pass.
- **Historical sources:** SPEIS and Fremtidens NATO-våpen document the
  provenance of NORDVAKT. Norwegian Hedge remains a historical quant-fund
  concept, not the active consumer-bank plan.

NORDVAKT combines the maritime and space/Arctic concepts into a civil-first
data and operations platform. It begins with existing, licensed data and
software pilots. It does not assume owned ships, satellites, weapons, NATO
procurement or partner agreements. Norwegian Financial reframes the former
quant concept as a partner-first financial-software and future-bank strategy.
Quantitative fund management remains separate from banking and customer
deposits. NEOLIMB is an exploratory translational-research concept for reconstructive
medicine. It is distinct from pub.healthcare and Fremtidens helse-OS: it builds
neither hospital infrastructure nor a general health-IT operating system.
Full-limb regeneration remains long-term research, not a clinical product or
a promised outcome.

The funding summary reads only the explicit `Innovasjon Norge` row in each
financing table. It does not treat total project capital, political fundraising
targets or bank-licence capital as grant requests. Funding sources remain
subject to applicant eligibility, scheme rules and evidence.

The portfolio may support applications to Innovasjon Norge and relevant
legater, but no plan is presumed eligible. Before submission, verify the
applicant, current call, eligible cost categories, matching funds, state-aid
limits and required evidence. Forecasts and proposed contributions are not
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

## Evidence register for legal and funding work

Every legal instrument and material funding proposal must carry an evidence register in its existing
working source. The register is part of the deliverable's provenance, not a bibliography of
convenient links. Keep one record per material claim or operative legal proposition, and one source
record for each authority relied on.

Each record must include: stable evidence ID; exact claim or clause supported; affected document and
section; source title and issuing authority; jurisdiction; canonical source URI or document
identifier; source version; publication date and effective-from/effective-to dates where applicable;
precise section, paragraph, table or page locator; retrieval date; last verification date;
verification method and result; limitations and contrary evidence; reviewer and review role; review
status; and next-review date for time-sensitive material.

Use explicit review states: `NOT_CHECKED`, `VERIFIED`, `PARTIAL`, `CONTRADICTED`, `SUPERSEDED` or
`OUT_OF_SCOPE`. A URL alone is a research lead, not evidence that a source supports a claim.
`VERIFIED` requires inspection of the cited primary passage and confirmation that its jurisdiction,
version and effective date apply to the relevant document and transaction date. Record an unverified
source as `NOT_CHECKED`; never quietly promote it from a search snippet, summary or model-generated
citation.

Keep verification history append-only. When an authority changes, retain the prior record and add a
new check with its new version, publication/effective dates and retrieval date. Funding records must
also capture the call's opening and closing dates, applicant eligibility, eligible cost rules, award
conditions and the date those requirements were checked. Where no authoritative source or effective
date can be established, mark the affected claim `PARTIAL` or `NOT_CHECKED` and keep the document
release gate closed.

A qualified legal review is a separate approval record: reviewer identity and competence,
jurisdiction, exact document version, review date, unresolved conditions and approval/rejection. A
checked legal source is not proof that the complete instrument is valid, enforceable or suitable for
signature. Automated checks remain a preparation aid; the existing lawyer-review requirement is
unchanged.

`BIZ/fetat/research.md` §2.4 is the existing claim-level example of this discipline. Reuse and
extend that record where appropriate; do not create a competing source ledger or imply that its
limited verification pass covers every BIZ document. The current build/check chain does not certify
legal instruments. No legal-document family may be marked published until its own evidence,
jurisdiction, consistency and qualified-human-review gates are implemented and passed.

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

## ## The folder law

Each published workstream folder contains only its reader-facing HTML, its
optional SVG mark and the PDF printed from that HTML. This keeps the published
pair together and avoids competing editable copies. Sources and production
tools live in `BIZ/tools/`, never inside a plan folder.

Active plan sources use `tools/<plan>.html`. NORDVAKT and Norwegian Financial
are authored as complete Bob2 documents; historical SPEIS, NATO and Norwegian
Hedge sources remain as provenance. The build/check/print/index chain uses
`bp_build.mjs`, `bp_retemplate.mjs`, `bp_check.mjs`, `bp_print.mjs` and
`bp_index.mjs`. Content modules are `plans_a.mjs`, `plans_b.mjs` and
`content_add.mjs`; the two new plans also have proposal sources.

Regenerate the published pair from those sources. Give each release attempt a fresh
scratch directory; the builders refuse to replace earlier generated HTML, PDFs or
cover images:

    export BIZ_OUT_DIR="$(mktemp -d)"
    node BIZ/tools/bp_build.mjs       # bases + additions -> BIZ_OUT_DIR
    node BIZ/tools/bp_retemplate.mjs  # bob2 skin onto the builds
    node BIZ/tools/bp_check.mjs       # MASTER Law scan + BIZ print/data contract
    node BIZ/tools/bp_print.mjs       # PDF, cover PNG and per-document print receipt

Review every full-page raster in the audit directory and the cover PNG yourself.
Only after you accept the appearance, copy each active plan's HTML, PDF, PNG
and `.print.json` from `BIZ_OUT_DIR/<plan>/` into its existing
`BIZ/<plan>/` owner directory. Ragnhild's guide HTML remains its source in
`BIZ/ragnhild/ragnhild_legater.html`; copy its generated PDF, PNG and
`ragnhild_legater.print.json` from `BIZ_OUT_DIR/ragnhild/`. Do not
bulk-publish drafts or replace an existing pair without preserving the prior
version. Then run:

    node BIZ/tools/bp_index.mjs       # verify published pairs and regenerate this index

`bp_check.mjs` delegates common HTML, prose and hygiene Laws to `MASTER/bin/operator lint` for the business-plan outputs and Ragnhild's funding guide. Business-plan checks remain specific to the Bob2/print contract and independently re-read financial arithmetic; the funding guide has a separate profile check for its five-page structure, accessible calendar headers, cited source links, source-check date and explicit eligibility/deadline caveats. The guide is not passed through the business-plan finance model or Bob2 skin.

`bp_print.mjs` checks `BIZ_CHROME_BIN`, then `CHROME_BIN`, then common
macOS and Linux Chrome/Chromium executable names. Set `BIZ_CHROME_BIN` to
the exact executable path only when automatic discovery cannot find it.
`bp_print.mjs` prints with headless Chromium (no Python anywhere in the
chain, per laws.yml REACH_non_native_tool) and checks every page size
against the hefte canon (156mm 234mm); it also verifies the funding guide's five-page output. Raster generation is not visual approval. `bp_print.mjs` writes a per-document `biz.print.v2` `.print.json` receipt binding the source HTML, every declared editable/build/check/print input, PDF and cover PNG by SHA-256, with page geometry and explicit `NOT_REVIEWED` visual/accessibility states. `BIZ/tools/paths.mjs` owns the single `PUBLISHED_INPUTS` manifest consumed by both printer and index. The printer checks these input hashes before and after rendering and refuses a receipt if an input changes during the run.. The receipt travels beside the published HTML/PDF/PNG and is not an approval record. `bp_index.mjs` requires matching receipts for active plans and Ragnhild's funding guide; it also fails if a published or archived link lacks its HTML/PDF pair, if its PDF predates its HTML, if a known editable source or print tool is newer than its corresponding published artifact, if a workstream directory is unlisted, or if the retained `bob`, `bob2` and `bob3` templates are missing or unpaired. The timestamp check is a local freshness tripwire, not a substitute for the receipt's hashes or for human review. It lists guidance separately from plans;
it derives the Innovasjon Norge request only from that explicit row in each
plan's financing table and reports source-only drafts separately. The retired
poise/cover generation (bp_cover.mjs) left with its generation; its history
is in git.

RESTORATION_REPORT.md beside this file records how the corpus was restored
and what the archive generations were.
