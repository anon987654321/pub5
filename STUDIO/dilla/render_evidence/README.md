# STUDIO/dilla/render_evidence — measured canon and render verdict

This directory holds the measured evidence that binds the engine to the
operator-curated Dilla canon. It follows `data/recovered_music.json`'s
`evidence_policy`: measurements are evidence of their class, never authority
over declared harmony; limits stay attached to the numbers.

## Files

- `measured_canon.json` — the full measured record: 13 rows measured from the
  curated list (SoundCloud title-matched with honest match classes) + 8 honest
  `no_match` rows. Per-stem band shares, onset grids, swing placement, tempo
  locks, mix chroma/Krumhansl.
- `render_vs_canon.json` — the closed-loop verdict: the rendered `dilla.wav`
  take (players, Ebm, 93 BPM, los_angeles) measured with the same analyzer and
  compared against the canon envelope. 6/6 bounded metrics inside the canon
  range.
- `RENDER_VS_CANON.md` — the human-readable verdict with the honest gaps.
- `tools/` — the pipeline that produced the record:
  - `dilla_stem_analyze.js` — pure Node analyzer (stdin: f32le mono 22050 Hz;
    stdout: one JSON). Band shares, onset flux, tempo autocorrelation, 16-slot
    best-phase grid, swing residuals, chroma + Krumhansl.
  - `assemble_evidence.sh` — assembles per-track stem analyses into
    `measured_canon.json` (was run against the sandbox analysis workdir).
  - `render_analyze.sh` — demucs-separates a rendered WAV and runs the same
    analyzer on its stems + mix.
  - `compare_render_canon.js` — computes the canon aggregates and the
    render-vs-canon verdict table.

## Regeneration

The SoundCloud harvest and demucs runs happened outside this checkout (datacenter
IPs are bot-walled on YouTube; the curated ids are matched by title, never
remixed). The tools above are reproducible against any working directory of
downloaded audio; `dilla_stem_analyze.js` has no dependencies beyond Node.

## Pointers

- Compact per-track summary + players row evidence: `data/recovered_music.json`
  (`measured_canon`, `progressions[].measured_evidence`).
- Engine anchors derived from these measurements: `data/showcase.json`
  (players_showcase, 93 BPM) and `data/dilla.json`
  (`production_profiles.j_dilla`, groove_profile los_angeles).
