# STUDIO

Media engines have one home here. Dilla is source-preserved with its four canonical JSON catalogues. Postpro and Replicate are separate plugins; their source remains gated until their dependencies and the shared HTTP/secret boundary are ported.

Generated media, reference audio, model weights and checkpoints are excluded from Git. Dilla renders go through Studio::OutputPaths to an external data directory. No output is generated as part of CI.

## Status

- Dilla: source preserved; runtime smoke test still required on Ruby 3.4.9.
- Postpro: source migration pending dependency and capability audit.
- Replicate: source migration pending migration to core HTTP and declared secrets.

`studio/projects.yml` is the current project and execution-status registry.