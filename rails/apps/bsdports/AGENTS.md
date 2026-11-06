# bsdports — agent notes

- **Domain:** bsdports.org. **Port:** 47312. **Deploy root:** `rails/apps/bsdports`.
- **Jobs:** `PortsImportJob` in `config/recurring.yml`; requires
  `db/queue_schema.rb` + Solid Queue on VPS.
- **Golden checks:** `openbsd/bin/check-rails --profile=contributor`.
- **VPS:** `master/bin/operator vps deploy bsdports --remote`.
- **Explore:** `Ports::ExploreAssistant` at `/ports/:id/explore`.


Porting state: source imported into `rails/apps/bsdports`; runtime, tests, production database restore and deploy adapter are NOT_RUN or BLOCKED. Do not deploy or touch vm23 from this branch.
