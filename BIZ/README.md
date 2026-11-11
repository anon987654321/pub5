# biz — eight concepts, one pair each

Restored from the pub, pub2 and pub3 archives into the pub5 anlage and
completed for Innovasjon Norge applications. One tree since 8 November 2026,
when the operator merged the published folders, the preserved BPLANS archive
and the tooling that lived in MASTER/tools/biz into the single BIZ tree you
are reading. Each concept is delivered as one self-contained HTML document
and one PDF printed from that same document, one folder per plan:

    syre/syre.html + syre.pdf                     3D-printede sko, NOK 250 000
    ragnhild/ragnhild.html + ragnhild.pdf         begravelsesbyrå (karaokekiste), NOK 150 000
    speis/speis.html + speis.pdf                  maritime og forsvar, NOK 500 000
    future_nato_weapons/…                         arktiske dominanseskip og polar SAR, NOK 500 000
    norwegianhedge/norwegianhedge.html + .pdf     Ruby-handelsroboter, NOK 300 000
    pubhealthcare/pubhealthcare.html + .pdf       autonome parametriske sykehus, NOK 500 000
    govt_bergen/govt_bergen.html + .pdf           bergensk selvstyre-teknologi, NOK 200 000
    future_healthcare_os/…                        helse-OS etter OpenBSD, Rails/Rhoda og MASTER, NOK 500 000

Eight concepts, sought funding in total: **NOK 2 900 000**. `future_nato_weapons`
is the 8 November 2026 merge of NATO Aurora with the space domain, by the
operator's order "nato and space merges into one new plan"; `future_healthcare_os`
followed the same day's order to model a healthcare OS on OpenBSD,
Rails/Rhoda and the MASTER trees. Both carry their source-of-truth proposal
in `tools/<plan>_proposal.md`, after the fetat setup.

`fetat/fetat.html + fetat.pdf` (Familieetaten) shares the folder layout; its
proposal, build and trace live in `tools/` under the `fetat_` prefix.
`ai3/` is preserved from the pub3/pub5 archives and is not in the keep-list
for this restoration. `__templates/` keeps the original bob, bob2 and bob3
correspondence in HTML and PDF form — historical source material, not
deliverables — and `research/` keeps the evidence notes.

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
paper ground belongs to the retired archive generation.

## The folder law

The folder carries only what the reader receives: the html, its svg mark
(where one exists) and the pdf printed from that html, so the pair cannot
drift. Editable sources and all tooling sit in `tools/`, never inside a
plan folder: all eight base documents (`tools/<plan>.html` — six restored,
two authored complete per their proposals), the build/check/print/index
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

`bp_check.mjs` delegates common HTML, prose and hygiene Laws to `MASTER/bin/operator lint`; its own checks are limited to the bob2/print contract and re-read financial arithmetic. The standalone print stylesheet carries a line-local `scan: intentional` marker because the document has no asset pipeline.

`bp_print.mjs` prints with headless Chromium (no Python anywhere in the
chain, per laws.yml REACH_non_native_tool) and checks every page size
against the hefte canon (156mm 234mm). `bp_index.mjs` fails if a folder
table row lacks its published pair or the funding total drifts. The retired
poise/cover generation (bp_cover.mjs) left with its generation; its history
is in git.

RESTORATION_REPORT.md beside this file records how the corpus was restored
and what the archive generations were.
