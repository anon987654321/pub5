# UNDERSTANDING — the Dilla tree

Rebuilt 2026-11-22 after a sandbox recycle (the previous copy was lost
before push). This is the restored understanding from the archaeology of
`pub`, `pub2`, `pub3` and `pub4`, plus the session record. It is the
taste layer: what makes good music good here.

## What the histories taught

- **Chord material is never invented.** Loops come from tried-and-tested
  artist material — the favourite artists and the artists they sampled.
  This is the ORIGINAL AUTHENTICS law (2026-11-22) and it outranks
  convenience.
- **Honesty over decoration.** Every claim carries a published source.
  When a claim cannot be verified it is labelled and kept visible
  (`authentics_audit.still_unverified`), never silently dropped or
  silently kept.
- **Tiers protect the canon.** Sample-verified artist rows and published
  charts are performance material. Engine studies and originals are
  exercises — useful for motion and sound, never presented as the
  artists' harmony. The menu order
  (artist_verified → chart_reference → engine_study → engine →
  recovered) makes the tiering visible to callers.
- **The human feel is the point.** Dilla's drum feel sits behind the
  grid (swing 54±1), melody is a heard layer, bass supports at -14 dB,
  and the mix is judged by measured energy shares, not by ear alone.
  Two masters were rejected as "horrible" before the mix protocol
  existed; iterate-and-keep with sidecars is how we do not repeat that.

## Engine facts

- `Dilla::ChordParser` has no bare "C" or open-fifth quality; spell the
  closing dominant as `Cmaj` and record the grid assumption in the row.
- `evidence_policy` is version 2 (`published_form` timing status and
  `source_refs` added). `dilla_test.rb` pins it; `rg69_defaults_test.rb`
  pins RG-69 markup defaults to engine boot values.
- RG-69 preset names (marvin, hathaway, wonder, tender) nod to artists;
  the loops are generic genre studies, not claimed transcriptions.

## The reference lane (canon input)

The operator's curated YouTube list — recovered verbatim from
`pub/index.html` at `a3185f4` — is the measurement canon for Dilla's
best work: J Dilla, Slum Village, Flying Lotus, Madlib, AFTA-1, Jay
Electronica, Samiyam, Chase Swayze, kemt, A. Mochi. The narrowed picks
(players, climax_girl_shit, microphone_master_remix, fantastic) go
through `ruby dilla.rb reference <rights-cleared URL or local audio> --style j_dilla`.
The Ruby standard-library analyzer measures the complete mix: tempo, swing,
onset density, harmony, spectral bands and energy. It does not separate stems,
so no isolated drum, bass or keyboard measurements are claimed. Mix-level
evidence about pocket and balance feeds the protocol above.

Sample identifications for the narrowed picks (WhoSampled, fetched
2026-11-22): Players <- Singers Unlimited "Clair"; Climax (Girl Shit)
<- Steve Miller Band "Space Intro" / "Fly Like an Eagle", Les McCann
"The Pleading"; Microphone Master (Jay Dee Remix) <- Clare Fischer "You
Call It Madness", Art of Noise "Opus 4", A Tribe Called Quest "Lyrics
to Go"; Fantastic <- Herbie Hancock "You'll Know When You Get There".

## Provenance note

The original understanding document and the audit commit were written
2026-11-22 but lost with the recycle before push. This copy was rebuilt
from the surviving audit script (`scripts/authentics_audit.py`), the
curated-picks script (`scripts/update_curated_picks.py`) and the
measurement selftest record (`download/dilla_reference/analysis/
pipeline_selftest.json`). The content matches the lost commit's
described state; the git history of the rebuild starts fresh.
