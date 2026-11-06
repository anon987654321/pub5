# Rails migration

The Rails source is being moved from pub4 into the selected R1 layout. This is
not a live application port yet. Pub4 remains the production source until the
pub5 contracts, runtime and restore gates pass.

## Tree ownership

- \`shared/\` is the common \`pub5-shared\` engine.
- \`brgen/\` is one city-network process. Its verticals live under
  \`brgen/engines/{dating,maps,marketplace,messenger,radio}/\`; playlist and TV
  remain radio-owned Brgen surfaces.
- \`amber/\`, \`bsdports/\` and \`mrdamascy/\` are independent applications.
- \`test/\` holds Rails-wide contracts. App and engine tests stay with their
  application.
- \`apps.yml\`, \`apps.horizon.yml\`, \`crawl_manifest.yml\`, package manifests,
  docs and parked plugins are migration inputs. \`registry/apps.yml\` remains
  the pub5 source of product facts.

## Current migration state

The first Brgen/Amber entry points and Amber icon have been copied into their
R1 paths. A partial BSDPorts source import still exists under the earlier
\`apps/bsdports\` path and must be reconciled into \`bsdports/\`. The shared
engine and the remaining Brgen, Amber and MrDamascy source have not completed
the R1 import. The OpenBSD registry renderer is a separate, unverified
migration increment.

A source copy is not proof of application readiness. Runtime, dependency,
route, signed-in journey, screenshot and database restore evidence must be
recorded before cutover. No production SQLite databases, Active Storage
uploads, account data, password digests, credentials, logs or caches belong
in this source port.
