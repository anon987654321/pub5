# bsdports

**Search the whole OpenBSD ports tree as fast as you can type.**
Each port has its own page with dependencies, security advisories and
maintainer details. Search returns matching ports as you type.

The app uses Rails 8.2.0.alpha on the installed compatible Ruby runtime
(3.2+), with SQLite, Falcon and Hotwire. Search reads an FTS5 index of port
names and comments stored in the same database.

The interface is an ultra-minimal white search surface inspired by the
classic Google front page: Arial, white background, `#202124` text,
`#4d5156` secondary text and `#1a0dab` links. Corners are square and port
results stay compact and exact. OpenBSD supplies the subject matter and
technical seriousness, not a dark terminal theme. The app follows the shared
engine's layout and accessibility contracts; its visual dialect differs
from Brgen and Amber, not its underlying interface grammar.

The interface defaults to Norwegian. The feature promise, stack and shipped
status live in `RAILS/apps.yml`, under `bsdports`.

The ports data arrives by import. The rake task `ports:import_now` reads a local tree at once.
Set `PLATFORM` to `openbsd` and `BSDPORTS_TREE_PATH` to `/usr/ports`, and it reports how many
ports it loaded. The task `ports:import` queues the same work on Solid Queue instead.
When no local tree is present, the importer tries the signed HTTPS ports tarball only when
`BSDPORTS_PORTS_TARBALL=1`, a matching trusted signify key and the `signify` executable are
available, and free disk space is sufficient. Otherwise it uses the thin package index. That
index updates package names and versions; it does not authoritatively describe dependency edges,
so an index-only import preserves previously known dependencies.

NVD cross-reference is asynchronous and operator-only. Set `BSDPORTS_ADMIN_EMAIL` in
`/etc/bsdports.env` to the operator account's email address; leave it unset to disable manual
cross-reference requests. `NVD_API_KEY` is optional and changes the shared request interval, not
the authorization boundary. Cross-reference jobs reserve distinct database-backed request slots,
and the scheduled refresh queues work instead of making NVD requests inside a web request or
bulk refresh thread.

The shared engine's social routes (notifications, reactions, reports) are off here, because the
schema has none of their tables. Setting `BSDPORTS_SOCIAL=1` draws them, and it should wait
until the migrations land. Conditional GET is on for a port page and a maintainer page, keyed on
the viewer, because those pages carry a watch button and a comment form. The shared README
gives the reasons.

A deploy runs through `OPENBSD/bin/vps-deploy bsdports`, which runs `bsdports.sh` on vm23 and
copies the tree to `/home/bsdports/app`. The shared engine sits beside it at
`/home/bsdports/__shared`. Every deploy sheds amber and bsdports together, and relayd keeps
answering TLS while their ports are closed, so a site that looks alive from outside can be
down underneath. After any deploy, prove that `127.0.0.1:47312` answers `/up` and `/health`.
Both matter, because `/up` says the process lives and `/health` says Solid Cache, Solid Queue
and the database are in order.

## Try it

```zsh
cd RAILS/bsdports
PLATFORM=openbsd BSDPORTS_TREE_PATH=/usr/ports bin/rails ports:import_now
bin/ci
```

Port pages can also open a compact SVG dependency overview, bounded to 60 indexed packages and six levels. The full text tree remains available; this view uses only recorded dependency rows.
