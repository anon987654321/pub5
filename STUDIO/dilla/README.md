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
ruby dilla.rb                          # curated showcase: Blue Hour — Dilla Minor Dub Cut
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
--mp3 --video/--no-video`. Kits: kit_dust / kit_break / kit_basement. Rigs:
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
(seed, performer, every flag). A render reproduces from its seed; without
one the seed and performer rotate per run — deleting a take loses it for
good, so keep what you like.

## Reference — learn from a recording

```sh
ruby dilla.rb reference https://www.youtube.com/watch?v=… [--style j_dilla]
ruby dilla.rb reference ~/crate/rights-cleared-loop.wav --no-stems
```

The reference analyzer is now **Ruby + standard library only**. It decodes
PCM/float WAV, downmixes and resamples to 22.05 kHz, runs a windowed FFT, and
measures tempo/confidence, onset density, offbeat share, timing spread, swing,
mix-band energy shares, brightness, key/chord changes, melody range/density,
16-step kick/snare/hat grids and section energy. Its output is finite,
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

`DILLA_OUTPUT_DIR` or `STUDIO/output_paths.rb` decides: the dated directory
under `$XDG_DATA_HOME/dilla-renders/`, falling back to `~/Downloads/dilla-renders/`.
`ruby dilla.rb output-path dilla-render-directory` and `output-path
reference-root` answer the same policy for MASTER. `out/`, `samples/` and
`crate/` inside this directory are yours; none of it is tracked.

## Tests

`cd STUDIO && rake check test` — the dilla suite covers the CLI contract
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
ruby STUDIO/bin/studio ableton inventory "$HOME/Ableton-Archive" --export-all
ruby STUDIO/bin/studio ableton export "$HOME/Ableton-Archive/My Set/My Set.als"
ruby STUDIO/bin/studio ableton midi "$HOME/Ableton-Archive/My Set/My Set.als" --out recovered.mid
ruby STUDIO/bin/studio ableton midi "$HOME/Ableton-Archive/My Set/My Set.als" \
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
