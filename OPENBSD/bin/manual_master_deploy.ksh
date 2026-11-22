#!/bin/ksh
# Retired recovery entrypoint. Never kill production processes or compile assets on vm23.
case ${1:-} in
-h|--help)
  echo "usage: ksh OPENBSD/bin/manual_master_deploy.ksh (retired; use workstation deploy command)"
  exit 0
  ;;
esac
echo "manual_master_deploy: refused - vm23 is not a build machine." >&2
echo "Build and attest MASTER/web assets on the workstation, then run:" >&2
echo "  MASTER/bin/operator vps deploy master --remote" >&2
exit 69
