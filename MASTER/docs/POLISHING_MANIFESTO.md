# Polishing Manifesto

Purpose: define what “done” means for MASTER and pub5 once every TODO and backlog item is cleared, and how continuous polishing is performed under the Laws.

## Authority

`data/soul.yml` → `data/laws.yml` → this manifesto → TraceStore signals → executable polish discovery.

Polishing never overrides constitutional identity or protected paths.

## Stance

- The backlog is empty. Remaining work is refinement of what already exists.
- Beauty, consistency, and unsurprising structure are continuous pressures, not periodic projects.
- MASTER itself discovers and implements polishing opportunities as part of `/fix` and background loops.
- Every applied polish leaves a durable trace and a verification receipt.

## Categories of polish

structure · naming · documentation · typography · accessibility · ui · ux · cli · interaction · resilience · provenance · performance · consistency · stigmergy · autopoiesis · principle · testability · operator · meta

## Severity

- cosmetic — visible only to careful readers; safe to batch.
- minor — small friction or inconsistency; preferred to fix promptly.
- moderate — affects operator experience or principle adherence; requires review.
- substantial — touches architecture or identity; human confirmation required.

## Stigmergy

Agents leave traces (metrics, tags, successful paths, verification outcomes). Other agents read those traces. Local patches may emit higher-order tags that cascade. Low-strength traces decay and are archived.

## Autopoiesis

A thin kernel regenerates a bounded set of its own components (scanners, oracles, collectors) while remaining under soul and law. The application surface stays allopoietic; the maintenance network aims for operational closure.

## /fix integration

`Polish::FixIntegration` is the bridge. Modes:

- `discover` — return opportunities only.
- `discover_and_emit` — write them into the TraceStore.
- `apply_safe` — apply only cosmetic/minor mechanical fixes and record receipts.

Product decisions, design reviews, and external actions remain human-gated.

## Next wave

When the current wave of opportunities is exhausted, MASTER re-scans under the same manifesto and produces the next wave. The process is itself subject to polishing.
