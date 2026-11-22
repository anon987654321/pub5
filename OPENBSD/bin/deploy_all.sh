#!/usr/bin/env zsh
# Compatibility entrypoint; admission, pinning, transport and canaries live in MASTER/bin/operator.
set -euo pipefail
SCRIPT_DIR=${0:A:h}
REPO_ROOT=${SCRIPT_DIR:h:h}
if [[ ${1:-} == --per-app ]]; then shift; fi
exec "${REPO_ROOT}/MASTER/bin/operator" vps deploy all --remote "$@"
