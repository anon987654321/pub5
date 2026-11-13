# MyToonz

AI comic-strip generator: a prompt becomes a Replicate prediction. Generation and bounded status polling run as background jobs; safe delivery images appear in the public gallery.

## Rails contract

Rails 8.2.0.alpha is pinned to the exact source revision in `RAILS/apps.yml#rails_stack`. The Gemfile and lockfile match the RAILS fleet. The app loads `pub5-shared` from `../__shared`; shared authentication, routes, reactions, localization helpers and guarded outbound HTTP stay in the engine. App-owned models and migrations stay here.

Norwegian is the default locale, with English as the fallback. The test suite follows the shared CI contract and covers authentication, model validation, provider URL allowlisting, explicit provider consent and bounded prediction polling.

Replicate credentials are read only from `REPLICATE_API_TOKEN`. They do not belong in source, logs, fixtures or Rails credentials. A provider request is not enqueued until a consent timestamp has been recorded. The consent copy explains that prompts go to Replicate and that its own terms and retention policy apply. Generated images are limited to HTTPS hosts under `replicate.delivery`.

## Provenance

The fuller Rails application was restored on 2026-11-13 from `anon987654321/pub4` parent commit `c11f9e7d91258044658e1320c3030a1d51f9fd5d` (2026-07-12), immediately before its removal by `3b25201f7e44ad253c7c86c38f7e0287432f95b5`.

The earlier generator prototype and standalone demo are retained in the history of `anon987654321/pub3`: `rails/mytoonz.sh` and `rails/mytoonz_demo.html` at commit `09663f79041452c48c5925998725d44719f59e67`.

## Operational boundary

This is a complete source application, not an approved production deployment. It remains outside `RAILS/apps.yml#apps`, deploy helpers and production health checks. Historical port 10008 is not reserved. No service, DNS, certificate, relayd route, production database or provider token was restored.

Before reactivation, require a fresh provider token, explicit privacy and retention review, real capacity and database evidence, an operator-approved OpenBSD deployment plan, and independently verified domain and port assignments. The old Docker/Kamal deployment files and GitHub Actions workflow remain excluded.
