#!/bin/ksh
# Record bounded RX/TX byte deltas for vm23's external interface.
# Thresholds are opt-in and must come from the provider's measured limits.
set -e
PATH=${PUB5_NETWORK_PATH_PREFIX:+${PUB5_NETWORK_PATH_PREFIX}/bin:}/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin
INTERFACE=vio0
STATE_DIR=${PUB5_NETWORK_STATE_DIR:-/var/db/pub5}
STATE_FILE=$STATE_DIR/network-$INTERFACE
HEARTBEAT_FILE=$STATE_DIR/network-watch.seen
LOG=${PUB5_NETWORK_LOG:-/var/log/network-watch.log}
ALERT_BIN=/usr/local/bin/pub5-alert
WARN_RX_BPS=${PUB5_NET_WARN_RX_BPS:-0}
WARN_TX_BPS=${PUB5_NET_WARN_TX_BPS:-0}

umask 077
mkdir -p "$STATE_DIR"

is_uint() {
  case $1 in '' | *[!0-9]*) return 1 ;; esac
  return 0
}

monitor_unavailable() {
  reason=$1
  printf '%s unavailable interface=%s reason="%s"\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$INTERFACE" "$reason" >> "$LOG"
  "$ALERT_BIN" raise network-monitor-unavailable "$reason"
  exit 1
}

is_uint "$WARN_RX_BPS" || monitor_unavailable "PUB5_NET_WARN_RX_BPS must be an integer"
is_uint "$WARN_TX_BPS" || monitor_unavailable "PUB5_NET_WARN_TX_BPS must be an integer"

stats=$(netstat -I "$INTERFACE" -b 2>/dev/null) || monitor_unavailable "netstat could not read $INTERFACE"
rx=""
tx=""
while IFS= read -r line; do
  set -- $line
  [[ ${1:-} == "$INTERFACE" ]] || continue
  # With -b, OpenBSD reports bytes in and out in the final two columns.
  while (( $# > 2 )); do shift; done
  if (( $# == 2 )); then
    rx=$1
    tx=$2
  fi
done <<EOF
$stats
EOF

is_uint "$rx" || monitor_unavailable "netstat returned no byte counters for $INTERFACE"
is_uint "$tx" || monitor_unavailable "netstat returned malformed byte counters for $INTERFACE"
stamp=$(date +%s)
is_uint "$stamp" || monitor_unavailable "date did not return an epoch timestamp"

write_state() {
  temporary=$STATE_FILE.$$
  printf '%s %s %s\n' "$stamp" "$rx" "$tx" > "$temporary"
  mv -f "$temporary" "$STATE_FILE"
  temporary=$HEARTBEAT_FILE.$$
  printf '%s\n' "$stamp" > "$temporary"
  mv -f "$temporary" "$HEARTBEAT_FILE"
}

if [[ ! -f $STATE_FILE ]]; then
  write_state
  printf '%s interface=%s baseline_rx_bytes=%s baseline_tx_bytes=%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$INTERFACE" "$rx" "$tx" >> "$LOG"
  exit 0
fi

read old_stamp old_rx old_tx < "$STATE_FILE" || monitor_unavailable "network baseline is unreadable"
is_uint "$old_stamp" && is_uint "$old_rx" && is_uint "$old_tx" || monitor_unavailable "network baseline is malformed"
elapsed=$((stamp - old_stamp))
if (( elapsed <= 0 || rx < old_rx || tx < old_tx )); then
  write_state
  printf '%s interface=%s counter_reset=1 baseline_rx_bytes=%s baseline_tx_bytes=%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$INTERFACE" "$rx" "$tx" >> "$LOG"
  exit 0
fi

rx_delta=$((rx - old_rx))
tx_delta=$((tx - old_tx))
write_state

# Long gaps are recorded but not compared to the normal five-minute average.
if (( elapsed > 900 )); then
  printf '%s interface=%s sample_gap_s=%s rx_bytes=%s tx_bytes=%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$INTERFACE" "$elapsed" "$rx_delta" "$tx_delta" >> "$LOG"
  exit 0
fi

rx_bps=$((rx_delta * 8 / elapsed))
tx_bps=$((tx_delta * 8 / elapsed))
printf '%s interface=%s elapsed_s=%s rx_bytes=%s tx_bytes=%s avg_rx_bps=%s avg_tx_bps=%s\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$INTERFACE" \
  "$rx_delta" "$tx_delta" "$rx_bps" "$tx_bps" >> "$LOG"

if (( WARN_TX_BPS > 0 && tx_delta * 8 >= WARN_TX_BPS * elapsed )); then
  "$ALERT_BIN" raise network-egress-high \
    "$INTERFACE outbound averaged ${tx_bps} bit/s over ${elapsed}s (configured limit ${WARN_TX_BPS} bit/s); inspect provider traffic report and connection owners"
fi
if (( WARN_RX_BPS > 0 && rx_delta * 8 >= WARN_RX_BPS * elapsed )); then
  "$ALERT_BIN" raise network-ingress-high \
    "$INTERFACE inbound averaged ${rx_bps} bit/s over ${elapsed}s (configured limit ${WARN_RX_BPS} bit/s); inspect provider traffic report and connection owners"
fi

exit 0
