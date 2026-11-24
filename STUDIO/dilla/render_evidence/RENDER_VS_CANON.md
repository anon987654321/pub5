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

---

# Re-check 2026-11-24 — engine 4.3.0, take players / seed 20261124

The verdict above was measured on 2026-11-22, before the analog work in
dilla 4.3.0 (per-stroke tune/decay drift, velocity-shaped click and crack, a
soft-knee tape stage). Nothing in the earlier record covers that engine, so
the protocol was re-run on the current one instead of being inherited.

Machine-readable record: `render_vs_canon_20261124.json`.

## Take identity

- progression `players` (recovered), Ebm, 93 BPM, 24 bars, seed 20261124
- style `j_dilla` -> drums `dilla_shadow_full`, kit `kit_dust`, voice
  `rhodes_mark1`, rig `dilla_night`, groove `los_angeles`, sonitex subtle
- rendered with `--overwrite`; wav SHA-256 `6361988…` is the file in
  `STUDIO/dilla/dilla.wav`, so the numbers below describe the committed audio

## Metric comparison (drums stem, n=13 canon rows)

| metric | render | canon median | canon range | verdict |
|---|---|---|---|---|
| drum swing position (%) | 48.6 | 49.6 | 45.0 – 52.8 | PASS |
| on-grid share (16-slot) | 0.39 | 0.66 | 0.35 – 1.00 | PASS |
| off-8th residual (ms) | -13.6 | -1.5 | -47.7 – +19.8 | PASS |
| kick low-band share (<130 Hz) | 0.738 | 0.672 | 0.375 – 0.807 | PASS |
| snare mid-band share (bp@400) | 0.082 | 0.099 | 0.055 – 0.202 | PASS |
| hat high-band share (>5 kHz) | 0.015 | 0.018 | 0.002 – 0.033 | PASS |

6/6 inside the canon envelope. Tempo: drums raw 62 folds to 93, mix locks
93.1 directly, inside the 85–95 window; 11/13 canon rows carry a mirror in
that window too.

## What the engine change did to the numbers

The same take was measured twice, before and after one edit.

| variant | swing % | on-grid | off-8th (ms) | verdict |
|---|---|---|---|---|
| with a 5 %-probability ±32 ms "scatter tail" | 47.7 | 0.39 | -21.9 | 6/6 |
| tail removed (committed) | 48.6 | 0.39 | -13.6 | 6/6 |

Both pass. The tail was removed anyway: it was a claim I had written into the
code as a comment ("measured records carry a scatter tail") without a canon
row behind it, and removing it moved the off-8th residual from -21.9 ms back
toward the canon median of -1.5 ms rather than away from it.

## Method trap, recorded so nobody repeats it

A two-stem demucs pass (`--two-stems=drums`) is **not** comparable to this
record. On the tail variant it reported an off-8th residual of **+36.3 ms**
and swing 53.8 %, both outside canon, while the four-stem pipeline measured
**-21.9 ms** and 47.7 % on the identical file. The two-stem "drums" output
leaks bass and chord material into the stem and drags the onset picker.
Canon comparisons use four stems or nothing.

## Honest gaps

- **Nobody has listened to this take.** `dilla.audit.json` says
  `technical_state: PASS`, `state: INCONCLUSIVE` because the listening
  checklist is unsigned. The canon metrics bound the groove and the band
  balance; they do not certify that it moves anyone.
- Key estimate: F minor, r=0.71, against a declared Eb progression. The
  analyzer's own `players` canon row estimates F major at r=0.26, and chroma
  cosine against the reference `players` mix is 0.844 (0.734 in the 2026-11-22
  record), so the harmony space matches even though the single-method key
  estimate disagrees. Not treated as evidence of a wrong key.
- Demucs here is 4.1.0 on torch 2.15 CPU; the canon rows were separated on the
  earlier host. Same model (`htdemucs`), same analyzer, different release.
- Levels not compared; canon rows are transcoded previews.
- `sample_flip=null`: no Dilla audio material is used. The claim is measured
  groove, band balance and harmony, not sample identity.
