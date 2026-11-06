# pub5

A clean successor to pub4, implemented against PLAN.md.

The trust-boundary layout is core/, master/, laws/, rails/, openbsd/, studio/, bplans/ and registry/. Core owns the seven World verbs and shared mechanisms. MASTER is assembled from capability-declared plugins. Laws carry detectors, fixtures and proof tests. Registry files hold canonical facts.

The port is contract-first: behaviour is locked in pub4 before a smaller implementation is accepted here. MASTER and soul/laws authority are ported last; pub4 remains authoritative until the new runtime passes its fixtures.

Production databases, Active Storage uploads, password digests and credentials are not copied into Git. M0 remains BLOCKED until every database and upload has a verified off-host restore and checksum inventory.

Unmeasured behaviour is INCONCLUSIVE, BLOCKED or NOT_RUN. A parse is not runtime proof; a rehearsal manifest is not live host evidence.

See PLAN.md for milestones and cutover rules, and AGENTS.md for the port contract.
