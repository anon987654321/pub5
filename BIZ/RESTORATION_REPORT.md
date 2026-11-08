# Restoration report — pub5.good BIZ, November 2026

The business-plan corpus was restored from the pub, pub2 and pub3 archives
into the pub5 anlage and completed for Innovasjon Norge applications. One
tree since 8 November 2026: the published folders, the preserved BPLANS
archive and the tooling that had moved to MASTER/tools/biz (Johann,
2026-11-07) were merged into the single BIZ tree this report sits in. The
plan folders carry only the published pair and, where one exists, the svg
mark; every editable source and all tooling live in `tools/` beside them.

Kept as-is, per the keep-list: pub4's FETAT working master (the proposal,
build and trace under the `fetat_` prefix in `tools/`; the published plan
folder `fetat/` carries only the trio). `ai3` is not in the keep-list; its
folder is preserved as archived material. The retired Python build scripts
are not in this repository; the converted `plans_a.mjs` and `plans_b.mjs`
are committed build inputs.

## What "complete" added (all restored plans)

Hvorfor nå · Kundeinnsikt og problemforståelse · Markedsføring og salg ·
Enhetsøkonomi · Milepæler og måltall · Resultatbudsjett 2026–2028 ·
Likviditetsbudsjett 2026–2028 · Risiko og risikoredusering · Behov for ekstern
kompetanse — placed inside the existing eight sections (the table of contents
is unchanged), all in the Bringhurst anlage with figure discipline. Every
number comes from the plans' own figures or from the operator's archive
documents; nothing is invented.

## MASTER laws.yml — research and compliance

The whole of `MASTER/data/laws.yml` and the relevant runtime sections of
`law_runtime.yml` (tool discipline, typography, Norwegian prose, visual
identity) were read before the build; the per-law notes live in
`research/`. The operative consequences:

- **REACH_non_native_tool** bans python, bash, sed, awk, head, tail, wc,
  perl; "Use Ruby" — but Ruby/zsh do not exist on the restoration host and
  cannot be installed (no root). The pipeline therefore runs on Node.js,
  which is not on the banned list, and invokes none of the banned commands.
  The retired Python scripts remain archived data, parsed as text, never
  executed.
- **PRESERVE_FIRST**: the archived anlage files are read-only sources; all
  completion content is inserted, never rewritten. Two reviewed exceptions,
  both cosmetic and recorded: CRLF/trailing-space/blank-line normalisation
  of the archived fractal SVG markup, and one Norwegian leech word
  («virkelig») removed from ragnhild's preserved prose under STRUNK_WHITE.
- **TRUTHFUL_STATUS / FINDING_HYGIENE / VERIFICATION_REQUIRED_FOR_COMPLETION**:
  checks that cannot parse their subject fail loudly as inconclusive instead
  of passing silently (two such defects were found and fixed in the verifier
  itself during the build).
- **Laws audit (November 2026)**: the plans are judged by the one Law system
  in `MASTER/`: `MASTER/data/laws.yml` holds every identity and `MASTER/law/`
  holds the detectors, so a plan is audited with `bin/check --profile=agent`
  rather than by a BIZ-local runner. Two such local runners that existed
  early (`fetat_laws.rb`, `laws_audit.rb`) were retired, because a Law has
  one statement and one detector. Their finding stands and is re-checkable:
  FAIL 0 across the plans, the restored bases swept clean of em dashes,
  straight-quote and double-space defects, the print canon
  (`@page 156 × 234 mm`, folio via `@bottom-center counter(page)`) imposed,
  and `text-align: justify` dropped from every prose rule (ragged right per
  BRINGHURST).

## The three generations

- **Archive generation (restored)**: EB Garamond embedded as data URLs,
  #F7F2E9 ground, poise cover revision on top (Bringhurst p. 61 "poise
  consists primarily of emptiness"; Strunk & White rule 17). Its front-matter
  pass lived in `bp_cover.mjs`, since retired with the generation it served;
  its history is in git.
- **bob2 generation (current)**: Johann, 2026-11-07: "all business plans
  must use bob2.html as starter template". The retemplate
  (`bp_retemplate.mjs`) re-skins every built document onto bob2's token
  vocabulary — --color-* tokens, body in Source Serif 4 and headings in
  EB Garamond from the Google Fonts link, the 66-character measure on one
  1.5 baseline grid, guillemets and true dashes, sentence-case titles, a
  white ground, the hefte print contract (156 × 234 mm, folio in the 12 mm
  foot, first page margin-free so the cover is the page) — while the content
  passes through untouched. `bp_check.mjs` enforces the vocabulary and the
  contract on every published plan.
- **One-tree generation (8 November 2026)**: the operator merged BPLANS and
  MASTER/tools/biz into BIZ; NATO Aurora and the space domain merged into
  `future_nato_weapons/`; `future_healthcare_os/` was added, modelled on
  OpenBSD, Rails/Rhoda and the MASTER trees. Both carry their
  source-of-truth proposal in `tools/`, are written directly on the bob2
  canon, and pass `bp_check.mjs` with zero failures.

## Verification results (November 2026)

- Page size of every PDF: 442.08 × 663.12 pt (156 × 234 mm, 2:3), verified
  by `bp_print.mjs` through `pdfinfo` for every plan it prints.
- Budget arithmetic: verified by `bp_check.mjs` re-reading every output
  file — resultat rows (inntekt + kost = driftsresultat; + finans =
  før skatt), likviditet sums and year-to-year balance continuity for all
  plans, and the financing tables. Zero failures.
- Law checks (lang, charset, single h1, heading hierarchy, final newline,
  tabs, trailing whitespace, blank-line runs, placeholders, line art,
  trailing arrows, leech words, character audit, font-face counts,
  wordmark-not-a-heading, bob2 tokens): zero failures.
- No placeholders (`TODO`, `XXX`, `【…】`, `undefined`, `NaN`) in any plan.

## Regenerating

The pipeline ships under `tools/` and shares `tools/paths.mjs`: the build
bases default to `tools/<plan>.html`, the BIZ tree root is derived from the
tool location (`BIZ_TREE` overrides), and build artifacts default to the
operating system's temporary directory (`BIZ_OUT_DIR` overrides). Chromium
and Poppler's `pdfinfo` are discovered on the host or selected with
`BIZ_CHROME_BIN` and `PDFINFO_BIN`.

    BIZ_OUT_DIR=/tmp/pub5-good-BIZ node BIZ/tools/bp_build.mjs       # bases + additions -> builds
    BIZ_OUT_DIR=/tmp/pub5-good-BIZ node BIZ/tools/bp_retemplate.mjs  # bob2 skin onto the builds
    BIZ_OUT_DIR=/tmp/pub5-good-BIZ node BIZ/tools/bp_check.mjs       # independent verification
    BIZ_OUT_DIR=/tmp/pub5-good-BIZ node BIZ/tools/bp_print.mjs       # PDFs via Chromium
    node BIZ/tools/bp_index.mjs                                      # index.html into BIZ/

The published pair is copied into the plan folder from `BIZ_OUT_DIR` after
the check passes. Read `bp_check.mjs` output with the same `BIZ_OUT_DIR` as
the build; with no `BIZ_OUT_DIR` it verifies the stale default-tmpdir
output. When the original Python data files are available elsewhere,
`BIZ_LEGACY_SOURCE_DIR` selects their directory for the optional one-time
`convert_content.mjs`.
