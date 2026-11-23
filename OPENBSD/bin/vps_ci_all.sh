#!/usr/bin/env zsh
# Retired: Rails CI runs on the workstation; production sync is owned by
# the pinned vps-deploy parent and must never run as a standalone bulk command.
set -euo pipefail

if [[ ${1:-} == -h || ${1:-} == --help ]]; then
  print "usage: zsh OPENBSD/bin/vps_ci_all.sh"
  print "  refused: run Rails bin/ci on the workstation and deploy through MASTER/bin/operator"
  exit 0
fi

print -u2 "vps_ci_all: refused - the standalone bulk sync/bundle path is retired"
print -u2 "run MASTER/bin/operator vps deploy rails --remote from the workstation"
exit 69
