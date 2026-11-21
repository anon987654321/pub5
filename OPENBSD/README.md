# OPENBSD

vm23 is pub5's production host. This tree owns its system configuration,
deployment tools and recovery procedures.

## Filesystem mirror

`OPENBSD/mirror/` is a filesystem image: each path beneath it maps to the
same path beneath the host root.

```text
mirror/etc/relayd.conf                  -> /etc/relayd.conf
mirror/usr/local/bin/resource_guard.sh  -> /usr/local/bin/resource_guard.sh
mirror/var/nsd/etc/nsd.conf              -> /var/nsd/etc/nsd.conf
```

The old `doas cp -R mirror/* /` command expresses the same basic idea. The
routine installer is its guarded equivalent; do not replace it with a blind
recursive copy.

From the repository root, inspect, apply and verify the mirror:

```sh
doas zsh OPENBSD/OPERATOR.sh --plan
doas zsh OPENBSD/OPERATOR.sh --apply
doas zsh OPENBSD/OPERATOR.sh --verify
```

The installer uses tracked regular files only. It backs up changed files,
validates supported configurations, installs their declared ownership and
mode, and activates affected services. It does not delete unrelated host
files. SSH configuration is protected; `doas.conf` has a separate guarded
path; the managed root crontab is merged rather than copied as a file.

## Full production release

From a clean workstation checkout on `origin/main`:

```sh
MASTER/bin/operator vps deploy all --remote
```

This pins one revision, applies the mirror, then deploys every active
application in `RAILS/apps.yml`, including MASTER's in-place web app.
Live-operation prerequisites and the direct `doas`/`rcctl` workflow are documented
in [RUNBOOK.md](RUNBOOK.md). Read it before SSH, `doas`, deployment, DNS, service
changes or recovery.

## Ownership

- `OPENBSD/mirror/` contains tracked filesystem payload, not operator tools.
- `OPENBSD/bin/`, `lib/`, `checks/` and `test/` contain the tooling and
  proof; they are not copied wholesale to the host root.
- `RAILS/apps.yml` is the application and domain source of truth.
  `deploy_inventory.json` is a generated deployment projection; regenerate
  it with `ruby OPENBSD/bin/sync_deploy_inventory.rb`, never edit it by hand.
- Host secrets remain in `/etc/*.env`; signed NSD zones remain host-owned
  under `/var/nsd/`. The root crontab source is
  `OPENBSD/data/root.crontab`.

Read [CLAUDE.md](CLAUDE.md) for operational sharp edges and
[PATH_OWNERSHIP.yml](PATH_OWNERSHIP.yml) before changing a path. The exact-release
manual and evidence requirements are defined in [RUNBOOK.md](RUNBOOK.md).
Render the local pub5 manual pages from the repository root:

```sh
MANPATH="$PWD/OPENBSD/mirror/usr/local/man" man -P cat 8 vps-deploy
```
