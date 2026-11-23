#!/usr/bin/env zsh
# Retired: repository scans and /fix never run on the production host.
# Keep this legacy path as an explicit refusal so old instructions cannot
# start a memory-heavy MASTER process on vm23.
set -euo pipefail

if [[ ${1:-} == -h || ${1:-} == --help ]]; then
  print "usage: zsh OPENBSD/bin/vps_master_scan.sh"
  print "  refused: run repository scans and /fix on the workstation or isolated sandbox"
  exit 0
fi

print -u2 "vps_master_scan: refused - repository scans are workstation/sandbox work; vm23 is production-only"
print -u2 "run MASTER/bin/master and /fix from the workstation checkout"
exit 69
