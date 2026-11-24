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

## Verify

From the repository root:

```sh
STUDIO/replicate/bin/studio doctor --json
cd STUDIO && rake check test
```

The checks use local fixtures and stubs. They do not prove a paid live transaction, a likeness review, a production render, or browser behavior. Those require their own explicit evidence.

See [the STUDIO project guide](../README.md) for the complete tool inventory, ownership boundaries and production contract.
