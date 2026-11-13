# Hjerterom

Restored source-only archive. This is the standalone food-rescue and redistribution Rails app: donations, food listings, weekly boxes, volunteer shifts, beneficiary matching, route planning and an operator dashboard.

## Provenance

Restored on 2026-11-13 from `anon987654321/pub4` commit `c11f9e7d91258044658e1320c3030a1d51f9fd5d` (2026-07-12), the complete parent tree immediately before the app was removed. The later production retirement is recorded in `RAILS/apps.yml` and `MASTER/docs/history/recovery/legacy_manifest.yml`.

## Pub5 integration

The app uses the local `pub5-shared` engine at `../__shared`. Shared routes and concerns must resolve from that engine; do not recreate a second shared implementation here. Keep migrations app-owned.

## Operational boundary

This tree is archived and is not a production deploy target. The vm23 service, user and home, rc.d entry, environment file, relayd route, certificate and DNS records were removed on 2026-08-12. Do not add Hjerterom to the active app inventory, deploy helpers, health checks or routing until an operator has approved a separate capacity, database, credentials and deployment plan.

The production database was not restored. Its historical backup is recorded at `/var/backups/pub4/hjerterom-20260812` on vm23. This repository contains schema and seed source, not the production SQLite data.

Historical Docker/Kamal files, GitHub Actions workflows and credential artifacts are intentionally excluded. Do not restore secrets to Git. No deployment or live-service claim follows from restoring this source tree.
