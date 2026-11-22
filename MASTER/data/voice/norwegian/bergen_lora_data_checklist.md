# Bergen high-tone LoRA data checklist

Goal: continue from AlexKjes/cosy-norwegian (`model_720_lora_state.pt`)
toward reliable Bergen high-tone + skarre-r. Provenance: salvaged from the
reviewed external patch (see README.md in this directory); this is a
data-collection plan for the operator, not a wired route.

## Priority data characteristics

1. **Uvular r (skarre-r)** - speakers who consistently use the uvular
   realisation, not alveolar r.
2. **No retroflexes** - natural separation of r + t/d/n/l/s.
3. **High-tone realisation** - tonem 1 with an early high peak then fall on
   the stressed syllable (the target `bergen.yml` pins).
4. **Two-gender morphology** - *boken, solen, jenten, døren* preferred in
   spontaneous speech.
5. **Local function words** - *eg, ikkje, ka, kæm, koffor, korleis, no*.

## Suggested data sources (open / collectable)

- NST / NPSC subsets with Vestland or confirmed Bergen speakers (filter if
  the metadata allows).
- Local radio / podcast / YouTube from Bergen, with permission or fair-use
  grounding for research.
- Read speech from native Bergen speakers: word lists and short paragraphs
  containing the minimal pairs, the high-frequency -en forms, and the
  clusters that would be retroflex in the East (barn, norsk, parti).
- Existing dialect corpora that tag region or r-variant.

## Minimum viable continued-training set

| Category                | Target              | Notes |
|-------------------------|---------------------|-------|
| High-tone tonem-1 words | 200–500 utterances  | sola, boka, døra, armen, bilen, huset |
| Skarre-r heavy sentences| 300+                | Multiple r's per utterance |
| Gender -en forms        | 200+                | Avoid -a forms in target transcripts |
| Everyday dialogue       | 1–2 h               | Natural prosody |
| Total new data          | ~3–10 h             | Quality over quantity for LoRA |

## Training notes

- Start from `model_720_lora_state.pt`, not from base only.
- Keep LoRA on the LLM frontend only (same stage-4 style).
- Use Bergen style prompts in training examples where possible.
- Evaluate with the fixtures in this directory:
  - F0 peak timing on tonem-1 words - early high, via
    `Voice::Benchmark.tonem_eval(path, accent: "bergen")`.
  - Absence of retroflexes and presence of uvular r (listening plus simple
    detectors).
  - Preference for -en vs -a in generated definite forms.

## Anti-targets (down-weight or avoid)

- Clear Eastern low-tone speakers.
- Heavy alveolar-r plus retroflex speakers.
- Over-represented Oslo / Eastern studio speech without filtering.
