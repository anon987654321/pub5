# MyToonz

A standalone Rails 8.2.0.alpha application for AI comic-strip generation. Prompts become Replicate predictions; generation and bounded status polling run as Solid Queue jobs, and safe delivery images appear in the gallery.

## Rails contract

- Pin Rails to the exact source revision in `RAILS/apps.yml#rails_stack`; keep the Gemfile and lockfile aligned with the RAILS fleet.
- Keep the app root at this directory. Load `pub5-shared` from `../__shared`; shared authentication, routes, reactions, localization helpers and guarded outbound HTTP belong to the engine.
- Keep app-owned models and migrations here. Migrations and schema defaults target Rails 8.2.
- Use `bin/ci` and the shared CI contract. Tests cover shared authentication, model validation, provider URL allowlisting and the consent/polling job boundary.
- Norwegian is the default locale; English is the fallback.
- Read the Replicate token only from `REPLICATE_API_TOKEN`. Never put provider credentials in source, logs, fixtures or Rails credentials.
- Do not enqueue a provider request without a recorded `provider_consent_at`. The UI must explain that prompts are sent to Replicate. Accept only HTTPS output URLs under `replicate.delivery`.

## Provenance

The fuller Rails application was restored on 2026-11-13 from `anon987654321/pub4` parent commit `c11f9e7d91258044658e1320c3030a1d51f9fd5d` (2026-07-12), immediately before it was removed by `3b25201f7e44ad253c7c86c38f7e0287432f95b5`.

The earlier generator prototype and standalone demo are retained in the history of `anon987654321/pub3`: `rails/mytoonz.sh` and `rails/mytoonz_demo.html` at commit `09663f79041452c48c5925998725d44719f59e67`.

## Operational boundary

This is source-complete, but not an approved production deployment. It remains outside `RAILS/apps.yml#apps`, deploy helpers and production health checks. Historical port 10008 is not active. No service, DNS, certificate, relayd route, production database or provider token was restored.

Before reactivation, require a fresh provider token, privacy and retention review, capacity and database evidence, an operator-approved OpenBSD deployment plan, and verified domain and port assignments. Do not restore Docker/Kamal deployment files or GitHub Actions workflows.
