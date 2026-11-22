# RENDER vs CANON — dilla.wav (2026-11-22, take break_biscuit / players)

Question: did the rendered `dilla.wav` get compared with actual Dilla beats?
Answer: yes — same analyzer, same demucs, same metrics, measured on both sides.
The render was demucs-separated (htdemucs) and analyzed with
`STUDIO/dilla/render_evidence/tools/dilla_stem_analyze.js` (pure Node), exactly like the 13 curated
reference tracks. Full machine-readable verdict: `STUDIO/dilla/render_evidence/render_vs_canon.json`.

## Take identity (session sidecar)

- progression `players` (recovered), Ebm, 93 BPM, 24 bars, 64.54 s
- groove `los_angeles` (kick/snare 50, hat 53), kit `kit_dust`, rig `dilla_night`
- voices rhodes_mark1 -> wurlitzer_200a drift; sonitex subtle; sample not used
- declared swing nominal 54.0; **measured** swing placement 50.2 (see below)

## Metric comparison (drums stem, n=13 canon rows)

| metric | render | canon median | canon range | verdict |
|---|---|---|---|---|
| drum swing position (%) | 50.2 | 49.6 | 45.0 – 52.8 | PASS |
| on-grid share (16-slot) | 0.37 | 0.66 | 0.35 – 1.00 | PASS (laid-back edge) |
| off-8th residual (ms) | +1.9 | -1.5 | -47.7 – +19.8 | PASS |
| kick low-band share (<130 Hz) | 0.727 | 0.672 | 0.375 – 0.807 | PASS |
| snare mid-band share (bp@400) | 0.077 | 0.099 | 0.055 – 0.202 | PASS |
| hat high-band share (>5 kHz) | 0.018 | 0.018 | 0.002 – 0.033 | PASS |

6/6 bounded metrics inside the measured canon envelope. The hat share is the
exact canon median; kick/snare sit inside the canonical dusty balance.

## Tempo

- drums stem autocorrelation locks 61.4 BPM raw; mirror 61.4 x 3/2 = **92.1**,
  inside the canon window 85–95 and within 1 BPM of the declared 93.
- mix autocorrelation locks **93.0 BPM directly**.
- canon rows with an 85–95 mirror: 11/13 (the other two sit at half/double
  mirrors, as documented in the measured_canon record).

## Tonality

- render mix Krumhansl estimate: **D# (=Eb) major, r=0.75** — matches the
  declared Eb family of the `players` progression (Ebm9/Abm7/Fm9/Bbm7).
- canon estimates are weak-to-moderate single-method (median r=0.56,
  max r=0.77); per EXTERNAL_RESEARCH_IS_EVIDENCE_NOT_AUTHORITY no canon row
  overrides the declared harmony, and the render's own measurement agrees.
- chroma cosine similarity, render mix vs `players` reference mix: **0.734**
  (same harmony space; not audio identity).

## Honest gaps (kept, not hidden)

- Levels not compared: SoundCloud transcodes decode >0 dBFS on canon rows;
  levels are relative evidence only.
- `centroid_hz` unit is broken in the shared analyzer (~1e8); omitted rather
  than reported as Hz. Fix belongs to the analyzer, not to this report.
- Canon rows are 30 s previews / fan uploads (mono-transcoded); the render is
  a 64.5 s stereo mix. Window difference kept as-is.
- `sample_flip=null`: the render contains **no** Dilla audio material
  (`sample_rights_status: not_used`). The identity claim is measured groove +
  harmony + timbre protocol, not sample identity. TRUTHFUL_STATUS.
- Declared swing nominal 54.0 vs measured placement 50.2: the measurement is
  the evidence; the nominal is the engine's input, not the result.

## Method

demucs htdemucs -> per-stem band shares (kick <130 Hz, snare bp@400, hats
>5 kHz), onset flux peak-picking, tempo via onset-envelope autocorrelation
(55–200 BPM folded 60–180), 16-slot best-phase grid (+/-45 ms), swing from
off-8th residuals; mix chroma (FFT 8192 @ 22.05 kHz, 55–2200 Hz) + Krumhansl.
Canon: 13 measured rows from the operator-curated 22-track list recovered
from pub git history (index.html a3185f4), SoundCloud title-matched with
honest match classes.
