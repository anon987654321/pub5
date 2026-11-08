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

The pipeline: **yt-dlp** pulls the source (URL) or the operator hands over a
local file, **demucs** separates drums / bass / other / vocals, and the
spectral analyzer (`reference_analyzer.py`, numpy + scipy) measures
tempo and confidence, onset density per bar, offbeat share, micro-timing
spread, swing ratio, per-stem energy shares, brightness, key and chord
changes, a melody summary and 16-step kick/snare/hat grids. The profile
lands in the reference root as `profiles/<style>/latest_profile.json`, and
the next render reads it through MASTER's media intent: pattern ranking,
pocket scaling and mix balance all come from the measurement.

YouTube bot-checks datacenter IPs. When it does, authenticate with your own
session: `DILLA_YT_COOKIES=/path/cookies.txt` (exported cookie file) or
`DILLA_YT_BROWSER=firefox` (browser profile). Without cookies the local-file
path still works end to end, and `--no-stems` skips separation for a
band-split analysis. Source audio must remain operator-supplied and
rights-cleared; this tool analyzes, it does not redistribute.

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

Use `--style` to select a local production profile: `j_dilla`, `flying_lotus`, `jazz_soul`, `funk`, `ambient`, `drum_and_bass`, or `noise_sound_design`. The FlyLo profile is an original jazz-fusion/electronic study based on the existing Coltrane Soup harmonic study and the FlyLo broken-beat pattern; it is not represented as a track transcription.

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
ruby dilla/lib/als_export.rb "$HOME/Ableton-Archive" --inventory "$HOME/Ableton-Archive/Ableton-Inventory.json"
ruby dilla/lib/als_export.rb "$HOME/Ableton-Archive/My Set/My Set.als"
ruby dilla/lib/als_to_midi.rb "$HOME/Ableton-Archive/My Set/My Set.als" --out recovered.mid
```

The directory form scans every `.als` recursively and writes an inventory with
tempo, time signature, track/clip/note counts, audio references and per-file
errors; one damaged set does not stop the scan. The single-file form writes a
versioned JSON composition archive and a standalone Ruby DSL archive beside
the source by default. Override destinations
with `--json PATH` and `--ruby PATH`. The MIDI command emits one track per
MIDI track, preserves beat-domain clip positions and note lengths, expands
enabled clip loops, pairs every note-on with its note-off, and routes tracks
named for drums/kits/beats to MIDI channel 10. Change tick resolution with
`--ppqn N` (default 960).

The parser extracts the project tempo and time signature, track identities and
names, MIDI/audio clips, clip positions and loop points, note pitch/start/
duration/velocity/enabled state, audio-file references and supported automation
event points. It does not reconstruct audio bytes, warp markers, Groove Pool
semantics, native instrument devices, effect racks, or plug-in state. Keep the
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
