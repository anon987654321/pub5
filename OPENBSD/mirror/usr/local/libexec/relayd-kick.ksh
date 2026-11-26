#!/bin/ksh
# Restart relayd after an app restart, so it drops connections to the old backend,
# and prove it came back. The rc.d scripts each ran `rcctl restart relayd || true`
# and never looked: on 2026-11-26 a restart from rc.d/master left relayd dead
# (ca: invalid relay hash) and every site refused HTTPS until a manual restart;
# relayd-watchdog would have healed it only at its next five-minute tick.
set -euo pipefail
attempt=1
while [[ $attempt -le 3 ]]; do
  /usr/sbin/rcctl restart relayd >/dev/null 2>&1 || true
  sleep 2
  /usr/sbin/rcctl check relayd >/dev/null 2>&1 && exit 0
  logger -t relayd-kick "relayd not running after restart attempt $attempt"
  attempt=$((attempt + 1))
done
logger -t relayd-kick "relayd still down after 3 restarts; relayd-watchdog retries every 5 minutes"
exit 1
