# MyToonz

AI comic-strip generator: a prompt becomes a comic-strip prediction through Replicate, with generation tracked by a background job and results shown in the comic grid.

## Stack

Rails 8.1 · SQLite · Falcon · Hotwire · Solid Queue · pub5-shared

## Pub5 integration

The local shared engine lives at `../__shared`. Shared authentication, routes, reactions and guarded outbound HTTP are used rather than copied into this app. The Replicate token is read only from `REPLICATE_API_TOKEN`; no credential belongs in source or Rails credentials.

## Recovery state

The full Rails tree was restored on 2026-11-13 from `anon987654321/pub4` commit parent `c11f9e7d91258044658e1320c3030a1d51f9fd5d`, before its removal on 2026-07-12. The earlier MyToonz generator and demo originate in `anon987654321/pub3` (`rails/mytoonz.sh` and `rails/mytoonz_demo.html`, commit `09663f79041452c48c5925998725d44719f59e67`).

It remains archived and is not in the active app inventory or deployment flow. Historical port 10008 is not reserved in pub5. No production database, provider token, service, DNS, certificate or relayd route was restored. The former Docker/Kamal deployment files and GitHub Actions workflow were not restored.

The current app sends the user's prompt text to Replicate when generation is enabled. Obtain explicit consent and review provider retention before any production use. Runtime and test readiness have not been established.
