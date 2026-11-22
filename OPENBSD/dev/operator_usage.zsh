#!/usr/bin/env zsh
set -euo pipefail
# Command-line usage text for OPENBSD/OPERATOR.sh.
# Sourced by the entrypoint; defines usage without executing it.

usage() {
  print -r -- "OpenBSD vm23 filesystem mirror (OPERATOR.sh).
Usage:
  doas zsh OPENBSD/OPERATOR.sh --plan
  doas zsh OPENBSD/OPERATOR.sh --apply
  doas zsh OPENBSD/OPERATOR.sh --verify
  doas zsh OPENBSD/OPERATOR.sh --apply --doas

Mirror contract:
  OPENBSD/mirror/etc/  -> /etc/
  OPENBSD/mirror/home/ -> /home/
  OPENBSD/mirror/usr/  -> /usr/
  OPENBSD/mirror/var/  -> /var/

Legacy first-install and staged recovery:
  doas zsh OPENBSD/BOOTSTRAP.sh --first-install
  doas zsh OPENBSD/BOOTSTRAP.sh --stage-1  # requires I_UNDERSTAND_DNS_WIPE=1
  doas zsh OPENBSD/BOOTSTRAP.sh --stage-2

The routine mirror installer does not install sshd_config or doas.conf
without their explicit guarded recovery paths. Root crontab is merged
from OPENBSD/data/root.crontab; it is not a filesystem mirror file."
}
