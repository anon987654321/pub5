# Norwegian accent evaluation fixtures

Evaluation data for Norwegian accent work (Bergen high-tone vs Eastern
low-tone), consumed by `Voice::Benchmark`'s tonem lane
(`lib/voice/benchmark.rb`: `pitch_track`, `tonem_verdict`, `tonem_eval`).

## Provenance

Salvaged on 2026-11-21 from an external agent patch ("master_voice") that
proposed a complete parallel TTS stack. The stack itself was rejected - it
registered its own engines, supervisor and G2P beside the existing
`Master::Voice::Engines` chain, returned `audio_path: nil` from every
adapter, rewrote the operator's words before synthesis, used bare Open3,
and shipped about 2,000 lines with no tests. The dialectology underneath it
was sound, so the data survives here in evaluation-only form. The review is
recorded in `data/proposals.yml` (entry `master-voice-parallel-stack`).

## What lives here

- `bergen.yml`, `oslo_standard.yml` - tonem-1 f0 targets, minimal pairs and
  word lists per accent. Read by `Benchmark.tonem_target`.
- `phonemes_bergen.yml`, `phonemes_east.yml` - segmental inventories
  (uvular vs alveolar r, retroflex series present vs absent).
- `bergen_lexicon.tsv` - reference forms for evaluation only, never a
  rewrite table. Hygiene applied on salvage: duplicate rows removed,
  identity mappings dropped, the contested `øya → øyen` and the approximate
  verb hints marked as such.
- `engine_comparison.md` - open-engine landscape for nb, corrected to the
  routing that actually exists in `data/tts.yml`.
- `bergen_lora_data_checklist.md` - data-collection plan for a future
  CosyVoice3 continued-LoRA attempt.

## Law statements

- This directory is **evaluation-only**. No engine, no supervisor, no voice
  selection: `data/voice.yml` `language_voices` remains the single source of
  truth, and Norwegian is spoken by Pernille until a real engine passes the
  benchmark gates.
- The synth contract is unchanged: an engine returns truthy only with a
  real audio file at `out_path`; failure returns false and never raises.
- Nothing here rewrites text before speech. Faithful speech is the default
  (`data/tts.yml`).

## Usage

```ruby
track = Master::Voice::Benchmark.pitch_track("solen.wav")
verdict = Master::Voice::Benchmark.tonem_eval("solen.wav", accent: "bergen")
# => { path:, accent:, target:, measured:, score:, pass:, available: }
```

`tonem_eval` needs `aubionotes` on PATH (the same optional dependency the
existing f0 summary uses) and answers nil, not an exception, when it is
missing or the audio is unreadable.
