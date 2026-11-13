# Hjerterom

Food rescue and redistribution: donations, food listings, weekly boxes, volunteer shifts, beneficiary matching, route planning and operator coordination.

## Stack

Rails 8.1 · SQLite · Falcon · Hotwire · OpenBSD

## Pub5 integration

The app loads the current local shared engine from `../__shared` via `pub5-shared`. Shared routes, authentication and concerns live there; app-owned migrations stay here.

## Recovery state

Source restored on 2026-11-13 from `anon987654321/pub4` commit `c11f9e7d91258044658e1320c3030a1d51f9fd5d`, immediately before the 2026-07-12 deletion commit. It remains an archived, source-only app. It is not listed in the active deploy matrix and has no live service, DNS, certificate or relayd route.

The historical production database backup is at `/var/backups/pub4/hjerterom-20260812` on vm23; it has not been restored. No production credentials are included.

Do not deploy or add infrastructure from this tree until an operator has approved capacity, database recovery, fresh credentials and a separate OpenBSD deployment plan. Historical Docker/Kamal deployment files and GitHub Actions workflows were not restored.
