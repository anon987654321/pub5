#!/usr/bin/env zsh
# Compatibility entrypoint. Production deployment is owned by MASTER/bin/redeploy.
set -euo pipefail
SCRIPT_DIR=${0:A:h}
REPO_ROOT=${SCRIPT_DIR:h:h}
if [[ ${1:-} == --per-app ]]; then shift; fi
exec "${REPO_ROOT}/MASTER/bin/redeploy" all "$@"
