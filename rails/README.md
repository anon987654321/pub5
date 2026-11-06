# Rails port

One shared engine, four Rails applications, and six Brgen vertical engines. The source is ported from pub4; the implementation is not declared live until its contracts and runtime checks pass.

## Ownership

- `shared/` owns common Rails behavior and the identical Brgen/Amber post-card, vote-rail and structural feed grammar.
- `apps/brgen/` will own the single city-network process; dating, maps, marketplace (including takeaway), messenger, radio (including playlist) and TV are engines inside it.
- `apps/amber/`, `apps/bsdports/` and `apps/mrdamascy/` are separate apps and processes.

Rails is pinned to stable 8.1.4.1 and Ruby 3.4.9. The canonical domain, feature and port facts stay in `registry/apps.yml`; `rails/port.yml` records migration state, not a second product registry.

Production SQLite databases, Active Storage blobs, password digests and credentials do not enter this source port. M0 is a hard cutover blocker until off-host restore and second-VM rehearsal evidence is recorded.
