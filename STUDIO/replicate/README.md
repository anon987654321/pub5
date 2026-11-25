# Replicate runtime

This project owns STUDIO's shared CLI, provider client, execution contracts, checks and regression suite. Dilla, LoRA and Postpro remain sibling project owners; this directory provides their common runtime and provider boundary.

## Entry points

- `bin/studio` is the unified operator CLI for Dilla, Postpro, subject-aware LoRA workflows, validation, recovery and publication gates.
- `client.rb` owns `Studio::ReplicateClient`, including schema-aware prediction inputs, bounded file transfers and explicit provider errors.
- `Rakefile` owns the shared check and test surface.
- `models.yml` is the STUDIO-side model catalogue. A catalogue row is not proof that a provider operation is available or enabled.

## Provider boundary

All provider URLs and response bodies are untrusted. Keep destination validation, DNS classification, socket pinning, TLS hostname verification, body limits, timeouts and redirect policy together at the provider boundary. Never turn a provider-returned URL into an unrestricted fetch, and never weaken the boundary with a direct `Net::HTTP.start(host)` call.

LoRA upload and training calls require a subject owner. They must pass the subject-specific consent and source-rights checks before any private media leaves the workstation. The runtime must not infer permission from a file's presence, a prior approval or a model version.

Provider calls can incur charges. Preflight the exact model schema and declared budget before upload or prediction; distinguish catalogue estimates from actual provider-reported cost. Missing cost data is unknown, not zero.

## Development chains

A still is not finished by one model. `chains.yml` declares a chain of
different Replicate models, and `chain.rb` runs it over the frame before any
local grade: each step uploads the previous step's output and hands it to
whichever image input that model declares. The house chain repairs, then
upscales, then emulates stock, so sharpening works on real detail and grain
sits on a repaired frame rather than on a raw prediction.

The chain is a default, not a flag. `Craft::STILL_CHAIN` names it, the series
and the CLI both pass it, and the capture receipt records each step's model and
the inputs it decided, never an uploaded URL. Every step is a paid prediction,
so a three-step chain costs three calls per frame; `--free` still applies to
the first render only.

## Promo cuts

`promo.rb` assembles the piece the subject watches. It takes stills and clips
in one call: clips lead, stills fill, one film look covers the whole cut and
`dilla.wav` runs underneath. A clip is trimmed to `clip_seconds`, fitted to the
frame, and crossfaded like a still, so a 12-second clip and a 4.5-second
portrait mix without arithmetic drift.

`segments_for_subject` chooses the material without being asked. If the subject
has clips under `STUDIO/lora/<subject>/<subject>_film_*.mp4`, the cut uses
them. Otherwise it uses the developed stills. `--subject merethe` needs no new
argument.

Clips cut together because each one starts where the last ended:
`Motion.last_frame` pulls the final frame of a clip and the next prediction
takes it as `first_frame_image`. `SelfieSeries#film_piece` does this in order,
and `#promo` hands the result to the cut.

## Verify

From the repository root:

```sh
STUDIO/replicate/bin/studio doctor --json
cd STUDIO && rake check test
```

The checks use local fixtures and stubs. They do not prove a paid live transaction, a likeness review, a production render, or browser behavior. Those require their own explicit evidence.

See [the STUDIO project guide](../README.md) for the complete tool inventory, ownership boundaries and production contract.
