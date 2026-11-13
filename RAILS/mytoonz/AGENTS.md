# MyToonz

Archived, source-only Rails app for AI comic-strip generation. Its retained implementation consists of a `ComicStrip` model, Replicate provider client, background generation job, browse/show/create screens and the original comic-grid styling.

## Provenance

The fuller Rails application was restored on 2026-11-13 from `anon987654321/pub4` parent commit `c11f9e7d91258044658e1320c3030a1d51f9fd5d` (2026-07-12), immediately before it was removed by `3b25201f7e44ad253c7c86c38f7e0287432f95b5`.

Its earlier generator prototype and standalone demo are retained in the history of `anon987654321/pub3`: `rails/mytoonz.sh` and `rails/mytoonz_demo.html` at main commit `09663f79041452c48c5925998725d44719f59e67`.

## Pub5 integration

The app loads `pub5-shared` from `../__shared`. Shared authentication, routes, reactions and outbound HTTP remain owned by that engine. App migrations remain here. The Replicate client uses `Shared::OutboundHttp`; it does not use HTTParty or make an unguarded network request.

## Operational boundary

This source is archived and is not a production deploy target. Historical port 10008 and the old deploy script are not active reservations. No service, DNS, certificate, relayd route, production database or credentials were restored. The old Docker/Kamal files and GitHub Actions workflow were intentionally excluded.

Before any reactivation, require a fresh provider token, explicit user consent for sending prompts to Replicate, a privacy/retention review, an operator-approved OpenBSD deployment plan, and real capacity and database evidence. No runtime readiness is implied by this source restoration.
