#!/usr/bin/env zsh
# Retired unsafe fast-push entrypoint. Production CI and release checks are mandatory.
set -euo pipefail
if [[ ${1:-} == -h || ${1:-} == --help ]]; then
  print "usage: MASTER/bin/operator vps deploy all --remote"
  exit 0
fi
print -u2 "vps_production_push: refused - fast deployment bypasses workstation CI and release checks."
print -u2 "Use: MASTER/bin/operator vps deploy all --remote"
exit 69
