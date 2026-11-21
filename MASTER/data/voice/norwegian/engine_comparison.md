# Norwegian TTS engine landscape (evaluation notes)

Focused comparison for Norwegian (Bokmål) accent work, status late 2026.
Provenance: salvaged from the reviewed external patch (see README.md in
this directory); ranks are proposals for future engine work, not wired
routes, and are corrected to what MASTER actually runs today.

## Ranking for future Norwegian engine work

| Rank | Engine                  | Norwegian Quality | Fine-tune Ease | Pitch Accent Potential | License          | Notes |
|------|-------------------------|-------------------|----------------|------------------------|------------------|-------|
| 1    | CosyVoice3 + NB LoRA   | High              | Excellent (LLM LoRA) | High (continue training) | Apache 2.0 + LoRA check | Proposed primary for Bergen work. AlexKjes LoRA on ~680h. |
| 2    | XTTS v2 (+ NB fine-tune)| Medium–High      | Good           | Medium–High            | CPML (non-commercial) | Best pure cloning. Community NB fine-tunes exist. License is the limiter. |
| 3    | Qwen3-TTS + community  | Medium (improving)| Good           | Medium                 | Apache 2.0       | Modern base. Active Norwegian fine-tune experiments. |
| 4    | Fish Speech / S2       | Medium            | Medium         | Medium                 | Restrictive      | High expressiveness. License friction for production. |
| 5    | Kokoro 82M             | Low               | Limited        | Low                    | Apache 2.0       | Fast English fallback only. Unfit as a Norwegian primary. |

## Detailed criteria

**Norwegian quality**
- CosyVoice3 + AlexKjes LoRA: the strongest currently available open path;
  trained on NST + NPSC material.
- XTTS v2: solid after a Norwegian fine-tune, still carries some foreign
  accent without further work.
- Qwen3-TTS: base is not Norwegian-native; community LoRAs are early.
- Kokoro: noticeably weaker out of the box, and it is already demoted in
  MASTER's chain for per-phrase latency, not only for quality.

**Fine-tune / LoRA ease**
- CosyVoice3: cleanest known path - LoRA on the Qwen2 LLM frontend is
  proven and efficient.
- XTTS v2: GPT encoder fine-tuning works but is more brittle.
- Qwen3-TTS: standard PEFT path.
- Kokoro: style presets rather than language adaptation.

**Pitch accent (Bergen high-tone) potential**
- Highest with CosyVoice3: the LLM stage carries prosody, and continued
  LoRA on high-tone data is straightforward.
- XTTS can improve with targeted data but has less explicit style control.
- The others lack demonstrated Norwegian tone control.

**License reality for MASTER**
- Prefer Apache 2.0 / MIT for long-term freedom: CosyVoice3, Qwen3-TTS,
  Kokoro.
- XTTS v2 is technically attractive but CPML blocks many uses; verify the
  specific LoRA's license separately.

## MASTER routing today (the reality this doc must not contradict)

- Chain (`data/tts.yml`): `mlx, chatterbox, glm_tts, edge_melodic, edge, say`
  - hosted glm_tts sits behind the local engines for the same per-phrase
    round-trip reason that demoted Kokoro.
- Norwegian voice: Pernille via Edge, pinned by `data/voice.yml`
  `language_voices` - the single voice truth. GLM serves no Norwegian voice,
  so pernille is deliberately unmapped in `glm_voice_map`.
- A CosyVoice3 / XTTS route would enter the same way every engine does: one
  `available?` / `synth` case arm in `lib/voice/engines.rb`, one chain line,
  stubbed contract tests, and the benchmark gates - not a second stack.
