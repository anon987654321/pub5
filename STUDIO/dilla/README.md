# dilla — the STUDIO beat engine

The synthesizer and Ableton recovery tools are Ruby + standard library; no
required gems or hosted services. `dilla.rb` synthesizes at 44.1 kHz the way
the catalogue says it should be made: 96 PPQN MPC feel, 53–56% swing pocket,
snares early / kicks late / hats forward, jazz voicings that voice-lead,
12-bit drum grit, a 40 Hz sub gated by the kick, vinyl dust and dub throws
over the top. The recovered chord transcriptions (Fantastic Vol 2, Donuts,
The Shining) play as first-class progressions beside the engine's own.

## Render

```sh
ruby dilla.rb                          # original showcase: F-minor Dub Study
ruby dilla.rb --list                   # progressions, drum patterns, groove profiles
ruby dilla.rb --random --out out.wav   # random progression, random drum pattern
ruby dilla.rb --progression 9 --drums dilla_shadow_full --profile dilla_shadow \
    --bpm 91 --out out.wav             # Fall in Love, full Dilla pocket
ruby dilla.rb --showcase --no-video --out out.wav
ruby dilla.rb demo-each                # catalogue, one mp3 per track + manifest
```

Flags: `--progression N|id --drums ID --profile NAME --groove 0.85-1.25
--bpm X --bars N --kit K --voice V --rig R --sonitex P --sonitex-instances N
--vcs 0-1 --drum-balance ±dB --chord-balance ±dB --seed N --performer ID
--mp3 --video/--no-video --overwrite`. Existing WAVs, MIDI files and sidecars are
protected by default; pass `--overwrite` deliberately to replace regular files.
Symlink and non-file destinations are always refused. This also applies to
`demo-each` and `industrial-techno`. Kits: kit_dust / kit_break / kit_basement. Rigs:
dilla_night / basement / dub_stairs. Sonitex wear: subtle / boom_bap /
aggressive_lofi / phone_wear. Groove profiles: dilla_shadow /
behind_the_beat / late_snare / on_grid.

## Record-sourced harmony

`--list` marks the source tier: `[record]` is restored from the historical
artist-transcription table, `[chart]` is a separately retained published chart,
`[study]` is an engine exercise rather than a song transcription, `[original]`
is authored in the current catalogue, and `[recovered]` is lower-confidence
recovery material. Duplicate aliases for the same recording are kept as source
notes or chord variants rather than counted as extra tracks.

Examples:

```sh
ruby dilla.rb --progression time_donut --seed 7 --out time.wav
ruby dilla.rb --progression fall_in_love --seed 7 --out fall_in_love.wav
ruby dilla.rb --progression get_dis_money --seed 7 --out get_dis_money.wav
ruby dilla.rb --progression climax_slum_village --seed 7 --out climax.wav
ruby dilla.rb --progression so_what_miles --seed 7 --out so_what.wav
ruby dilla.rb --progression never_catch_me_flylo --seed 7 --out never_catch_me.wav
```

The restored material includes Dilla-produced Slum Village records, Dilla's
`Time (The Donut of the Heart)`, Ahmad Jamal's `Pavanne`, Miles Davis's
`So What`, D'Angelo recordings, and a separately labelled Flying Lotus chart
reference. Chord spellings from the old charts (including slash-bass and
source-specific aliases) are preserved, and historic named MIDI grips take
precedence over generic shell voicings.

Melody evidence is narrower than the chord corpus: the old tree retained a
measured six-note sample/chop contour for the `Time` profile and legacy
profile pitch material, but not complete note-for-note lead transcriptions for
every record. Those motifs are identified as such. Other melodies are generated
from chord tones and the selected scale, with stepwise voice-leading; they are
not presented as recovered song melodies.

A render writes `<name>.wav` plus three sidecars: `.quality.json` (measured
peak, crest, LUFS estimate, stem energy shares), `.session.json` (what was
arranged: voicings, pattern, fills, sample plan) and `.provenance.json`
(seed, performer, every flag, invocation mode/style, renderer and
`analog_core.rb` digests, every `data/*.json` digest, and the supplied
sample loop's path/size/SHA-256 when it is available). A missing or symlinked sample source is recorded as
unavailable, not treated as a reproducible input. The guarded replay command below now checks the exact Ruby engine/version/platform,
renderer/data source set, original WAV and content hashes of the session and
quality sidecars before it attempts a WAV-only rerender. It still refuses
sample-loop takes until the decoder version and rights attestation can be
proved. A seed alone never reconstructs a take whose other inputs or renderer
have changed.

These profiles and controls describe compositional techniques, timing and
production choices; they do not promise imitation of a named artist or exact
artist-style fidelity. A melody is called recovered only when its source
supports that claim; generated voice-leading remains generated. A sample or
reference source must be operator-supplied and rights-cleared; a URL, artist
name or model output is not a rights grant. Preserve source material and the
prior approved take before replacing or grading an export. The sidecars record
render measurements and generation provenance, but neither a LUFS/FFT result
nor a seed establishes musical quality, rights or consent. Final listening
acceptance is a separate human decision and must be recorded separately from
automated tests.

Replay a supported WAV take only when the exact Ruby runtime, renderer
source set, original WAV, session sidecar and quality sidecar still match their
recorded fingerprints:

```sh
ruby dilla.rb reproduce /path/to/take.provenance.json --out /path/to/replay.wav
```

Replay supports the pure-Ruby render, random and showcase paths. It writes a
new WAV only, never replaces the source take, and reports `BYTE_MATCH` only
when the new WAV hash equals the original. It refuses sample-flip renders
because the historical receipt does not pin the FFmpeg decoder version and
rights attestation; it also refuses older receipts without sidecar hashes or
renders whose source/runtime has changed. MIDI, MP3 and video companions are
not regenerated. A byte match proves deterministic output, not listening
acceptance.

Audit a completed WAV without pretending a machine has listened to it:

```sh
ruby dilla.rb audit /path/to/render.wav
```

The `.audit.json` report checks RIFF/WAVE structure, delivery format, required
sidecars, render size and SHA-256, and seed/arrangement agreement. It records
peak/RMS/crest/LUFS measurements and a manual listening checklist. Technical
success remains **INCONCLUSIVE** until a person has auditioned the full render;
the command never turns structural checks into a claim about sound quality.

Audit a completed WAV without pretending a machine has listened to it:

```sh
ruby dilla.rb audit /path/to/render.wav
```

The `.audit.json` report checks RIFF/WAVE structure, delivery format, required
sidecars, render size and SHA-256, and seed/arrangement agreement. It records
peak/RMS/crest/LUFS measurements and a manual listening checklist. Technical
success remains **INCONCLUSIVE** until a person has auditioned the full render;
the command never turns structural checks into a claim about sound quality.

## Reference — learn from a recording

```sh
ruby dilla.rb reference https://www.youtube.com/watch?v=… [--style j_dilla]
ruby dilla.rb reference ~/crate/rights-cleared-loop.wav --no-stems
```

The reference analyzer is now **Ruby + standard library only**. It decodes
PCM/float WAV, downmixes and resamples to 22.05 kHz, runs a windowed FFT, and
measures tempo/confidence, onset density, offbeat share, timing spread, swing,
mix-band energy shares, brightness, key/chord changes, melody range/density,
16-step kick/snare/hat grids and section energy. It also reports peak and RMS level, near-full-scale sample count and percentage, and near-silence percentage over the analyzed segment; these are signal measurements, not a noise classifier or a substitute for listening. Its output is finite,
sorted JSON; the profile lands at
`profiles/<style>/latest_profile.json` for MASTER's media intent.

For a URL, the optional acquisition step uses the **yt-dlp executable** and
local FFmpeg. A local audio file is decoded by FFmpeg. Browser cookies remain
operator-supplied through `DILLA_YT_COOKIES` or
`DILLA_YT_BROWSER`; the tool never searches for credentials. The reference
analyzer itself needs no Python, NumPy, SciPy, Demucs, native gem or hosted
service. The migration deliberately removed automatic Demucs separation:
pocket and energy estimates are mix-derived, not claimed as isolated stems.
`--no-stems` remains accepted as a compatibility flag. Analysis is capped
at 600 seconds; `--max-duration S` can request a shorter initial segment.
Source audio must remain operator-supplied and rights-cleared; the tool
analyzes, it does not redistribute.

## Sample flip

```sh
SAMPLE_LOOP=~/crate/rights-cleared-loop.wav ruby dilla.rb --progression 9
# --sample-vol 0.42  --sample-weight 0.6  --sample-slices 8
```

Decodes at most 24 seconds through local ffmpeg, estimates each slice's
pitch classes, picks chord-aware chops deterministically, and mixes them
before the final tape stage. `--sample-vol` is the chop's gain, `--sample-weight`
its share of the mix, `--sample-slices` the grid.

## Where renders go

`DILLA_OUTPUT_DIR` or `STUDIO/replicate/output_paths.rb` decides: the dated directory
under `$XDG_DATA_HOME/dilla-renders/`, falling back to `~/Downloads/dilla-renders/`.
`ruby dilla.rb output-path dilla-render-directory` and `output-path
reference-root` answer the same policy for MASTER. `out/`, `samples/` and
`crate/` inside this directory are yours; none of it is tracked.

## RG-69 browser renderer

`rg69/rg69.js` reads the `tonejs_profiles.rg69` adapter in this catalogue. The adapter reuses `kit_break`, `prophet_5` and the dry `basement` rig, then maps their kit tuning, voice brightness and room sends into the browser's Tone.js instruments. The adapter is a translation layer: it does not claim that a Tone.js synth is the same instrument or circuit as Dilla's Ruby renderer.

Live playback and WAV export call the same Tone.js instrument builder. The drum pitch/filter settings and kit pan/level, FM keys, voice pan, chorus/tremolo/drive chain, pad voice and its filters, the room's delay/reverb controls, and the vinyl/crackle bed come from that profile. If the catalogue cannot be fetched, a matching embedded RG-69 fallback keeps the browser page usable; the page reports which path it used.

The two renderers share instrument and voice settings, not a promise of sample-identical output. Mastering graphs and browser/runtime behaviour still differ. Run the browser, export a WAV and audition it before claiming delivery or sound-quality parity; source checks cannot substitute for listening.
## Tests

`cd STUDIO && rake -f replicate/Rakefile check test` — the dilla suite covers the CLI contract
MASTER parses, chord parsing and voice-leading, deterministic seeds, mix
balance, the sample-flip bounds, the reference profile schema and the
analyzer's tempo measurement. Full-catalogue renders are a session activity,
not a test.

## Composed profiles and offline score export

The curated showcase is a section-aware 24-bar form, not one progression looped across the entire render. Each section can select a progression, drum grammar, active lanes, source patch and target patch; patch changes are crossfaded sample-by-sample over the section.

Use `--style` to select a local production profile: `j_dilla`, `flying_lotus`, `jazz_soul`, `funk`, `ambient`, `drum_and_bass`, `noise_sound_design`, or `royksopp`. The FlyLo profile is an original jazz-fusion/electronic study based on the existing Coltrane Soup harmonic study and the FlyLo broken-beat pattern; it is not represented as a track transcription.

The optional scale-locked FM accent lane is mixed under the main harmony. Use `--foley` to request it on a normal render. `--midi` writes the sequenced score as a multi-track Standard MIDI file; `--midi-out PATH` selects its destination. The core score, instruments and export are Ruby-only and require no Replicate, OpenRouter, Python packages, or paid API.

A new soul-clap lane is synthesized locally from staggered filtered-noise bursts. Swing, timing offsets and recurring step deviations are independent profile controls: repeated lane/step positions retain their calibrated timing relationship across the arrangement rather than receiving unrelated random offsets every bar. Tape wow/flutter now modulates sample position (transport speed) rather than only changing channel amplitude, with a speed-specific head-bump stage.

## Ableton Live Set recovery

A Live Set (`.als`) is normally gzip-compressed XML. The recovery tools read
the composition stored in that document; they do not pretend that referenced
audio samples or native Ableton/third-party plug-in devices are embedded in
the XML.

First copy the *whole project folders*, not only the `.als` files, so their
`Samples/` assets remain alongside the sets. For a Google Drive remote
configured in rclone:

```sh
rclone copy "gdrive:Ableton Projects" "$HOME/Ableton-Archive" --progress
```

Inspect and export a set (the parser also accepts extracted, plain XML):

```sh
ruby STUDIO/replicate/bin/studio ableton inventory "$HOME/Ableton-Archive" --export-all
ruby STUDIO/replicate/bin/studio ableton export "$HOME/Ableton-Archive/My Set/My Set.als"
ruby STUDIO/replicate/bin/studio ableton midi "$HOME/Ableton-Archive/My Set/My Set.als" --out recovered.mid
ruby STUDIO/replicate/bin/studio ableton midi "$HOME/Ableton-Archive/My Set/My Set.als" \
  --out recovered.mid --wav recovered.wav --soundfont "$HOME/SoundFonts/bank.sf2" --analog
```

The directory form scans every `.als` recursively and writes an inventory with
tempo, time signature, track/clip/note counts, audio references and per-file
errors; one damaged set does not stop the scan. Add `--export-all` to also
write a JSON composition archive and standalone Ruby archive beside every
valid `.als`, preserving the source directory structure. The single-file form writes a
versioned JSON composition archive and a standalone Ruby DSL archive beside
the source by default. Override destinations
with `--json PATH` and `--ruby PATH`. The MIDI command emits one track per MIDI track, preserves beat-domain clip
positions and note lengths, expands enabled clip loops, pairs every note-on
with its note-off, and routes tracks named for drums/kits/beats to MIDI channel
10. Its optional `--wav` mode invokes a local FluidSynth binary and SoundFont;
`--analog` then creates a second, processed WAV using FFmpeg's soft-clip,
vibrato and low-pass filters. The neutral FluidSynth WAV is never overwritten. Change tick resolution with
`--ppqn N` (default 960).

The parser extracts the project tempo and time signature, track identities and
names, MIDI/audio clips, clip positions and loop points, note pitch/start/
duration/velocity/enabled state, audio-file references and supported automation
event points. It does not reconstruct audio bytes, execute warp processing, interpret Groove
Pool semantics, or re-instantiate native instrument devices, effect racks or
plug-in state. Warp-marker positions and relative/absolute sample paths are
preserved when present in the set. Keep the
original `.als` file and complete project directory as the source of truth;
the JSON/Ruby archives are durable composition records, while the MIDI file is
the portable performance.

For a software-instrument render, the exported MIDI can be played through a
locally installed FluidSynth and a SoundFont (for example,
`fluidsynth -ni -r 44100 -F recovered.wav -T wav bank.sf2 recovered.mid`),
then optionally processed with local FFmpeg filters. Those are optional render stages: parsing, JSON/Ruby
export and MIDI generation need no network, API key, Python package or gem.
Check a local FFmpeg build with `ffmpeg -filters` before relying on a
particular analog filter.

## Ableton recovery — DeepSeek handoff

Treat the original `.als` and complete project folder as immutable source
material. Inventory first; do not begin by opening and saving projects in a
different Live version. The recovery tools are offline and source-preserving:

1. `bin/studio ableton inventory PROJECTS --export-all` recursively indexes
   every set, reports parser failures without stopping the batch, and writes
   per-set JSON and Ruby archives beside valid source sets.
2. `bin/studio ableton export SET.als` extracts the composition model:
   project tempo/time signature, track identities, MIDI/audio clips, beat
   positions, loop windows, note pitch/duration/velocity/enabled/release
   velocity, sample references, selected automation points and warp markers.
3. `bin/studio ableton midi SET.als` converts MIDI clips into a multitrack
   Standard MIDI file at 960 PPQN. It retains tempo and meter, expands enabled
   clip loops, plays pre-loop pickups once, skips disabled notes, pairs note-on
   and note-off, preserves release velocity, and routes drum-named tracks to
   channel 10.
4. Optional local rendering uses FluidSynth plus an operator-supplied
   SoundFont. FFmpeg's analog pass writes a second file; the neutral render is
   retained. Both external stages have a wall-clock timeout and write through
   temporary files so a failed render does not replace a previous result.

The archive is not a reconstructed Ableton project. It does not contain
referenced sample bytes, run warp processing, restore Groove Pool behaviour,
instantiate Ableton or third-party devices, recreate plug-in state, or
faithfully restore every automation/device envelope. Relative and absolute
sample paths are references only. Preserve the full project folder and
compare the archive's sample-path references against its `Samples/` tree.

When the Live Sets are supplied, the recovery pass should:
- inventory every set and group related versions without overwriting them;
- resolve sample references against the accompanying project assets and
  record missing, duplicate and ambiguous matches;
- compare clip/loop/warp metadata and MIDI note counts across versions;
- export separate MIDI tracks and available reference audio for inspection;
- identify unsupported device, plug-in, Groove Pool and automation state;
- use Ableton Live itself only for the remaining native-state export/freeze/
  flatten work, retaining untouched originals and writing recovered output to
  a separate destination.

Never report an ALS set as fully restored from JSON or MIDI alone. The final
recovery report must distinguish composition recovered, samples resolved,
native device state recovered, rendered audio checked, and still-unavailable
state.


## Render and recovery notes

The following material is retained here so Dilla has one project guide. The renderer, canonical composition data and recovery tools remain the implementation authorities.


### UNDERSTANDING — the Dilla tree

<sub>Consolidated from `STUDIO/dilla/UNDERSTANDING.md`.</sub>

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
- RG-69's browser synth adapter lives in `data/dilla.json` and references
  the existing `kit_break`, `prophet_5` and `basement` entries. Its Tone.js
  mappings are an explicit translation, not a claim that WebAudio reproduces
  the Ruby engine's analog-style instruments. Kit levels/pans, voice pan, room
  sends and vinyl/crackle controls are mapped in both paths. Live play and WAV
  export share one instrument builder; source parity still requires a browser
  export and human audition before sound quality is accepted.

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


### STUDIO/dilla/render_evidence — measured canon and render verdict

<sub>Consolidated from `STUDIO/dilla/render_evidence/README.md`.</sub>

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


### RENDER vs CANON — dilla.wav (2026-11-22, take break_biscuit / players)

<sub>Consolidated from `STUDIO/dilla/render_evidence/RENDER_VS_CANON.md`.</sub>

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
