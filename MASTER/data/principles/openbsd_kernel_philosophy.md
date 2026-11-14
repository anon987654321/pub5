---
name: OpenBSD kernel design philosophy
description: Correctness, small interfaces, explicit authority, and evidence-backed change.
type: project
---

This note preserves the OpenBSD-inspired design lineage; it is not a second registry of normative requirements. Binding requirements, Law identities and their execution/evidence contracts are owned by MASTER/data/laws.yml and its declared Law/check implementations. The one-owner rule in SINGULARITY_NORMATIVE_GUIDANCE_HAS_ONE_LAW_IDENTITY applies to this note as well.

The philosophy it records is that simplicity can shrink the audit surface; correctness grounds security; abstractions should earn their cost; each fact should have one owner; authority and side effects should cross explicit reviewable boundaries; unknown safety should fail closed while outcomes remain truthful; invalid states should be exposed early; contracts and side-effect order need before/after evidence; platform differences belong at real seams. A completed command is not proof.
