#!/bin/ksh
# Sample five one-second CPU intervals, publish a short-lived pressure signal,
# and retain process identity only (never command arguments or environments).
set -e
PATH=${PUB5_CPU_PATH_PREFIX:+${PUB5_CPU_PATH_PREFIX}/bin:}/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin
STATE_DIR=${PUB5_CPU_STATE_DIR:-/var/db/pub5}
LOG=${PUB5_CPU_LOG:-/var/log/cpu-watch.log}
ALERT_BIN=/usr/local/bin/pub5-alert
PRESSURE_FILE=$STATE_DIR/cpu-pressure
HEARTBEAT_FILE=$STATE_DIR/cpu-watch.seen

umask 077
mkdir -p "$STATE_DIR"

sample_failed() {
  reason=$1
  "$ALERT_BIN" raise cpu-monitor-sample-failed "$reason"
  exit 1
}

# OpenBSD vmstat -c 6 gives one since-boot row followed by five one-second
# interval rows. The final three columns are user, system and idle percentages.
vmstat_out=$(vmstat -c 6 2>/dev/null) || sample_failed "vmstat -c 6 failed"
sample_total=0
interval_count=0
busy_sum=0
high_count=0

while IFS= read -r line; do
  set -- $line
  case ${1:-} in
    '' | *[!0-9]*) continue ;;
  esac
  while (( $# > 3 )); do shift; done
  (( $# == 3 )) || sample_failed "vmstat CPU row did not end with three fields"
  user=$1
  system=$2
  idle=$3
  case $user$system$idle in *[!0-9]* | '') sample_failed "vmstat CPU fields were not numeric" ;; esac
  if (( user > 100 || system > 100 || idle > 100 )); then
    sample_failed "vmstat CPU percentage exceeded 100"
  fi
  cpu_total=$((user + system + idle))
  if (( cpu_total < 98 || cpu_total > 102 )); then
    sample_failed "vmstat CPU percentages did not sum to 100 (got $cpu_total)"
  fi

  sample_total=$((sample_total + 1))
  # vmstat's first row is the since-boot average, not a one-second interval.
  if (( sample_total == 1 )); then continue; fi

  busy=$((100 - idle))
  busy_sum=$((busy_sum + busy))
  interval_count=$((interval_count + 1))
  if (( busy >= 80 )); then high_count=$((high_count + 1)); fi
done <<EOF
$vmstat_out
EOF

if (( sample_total != 6 || interval_count != 5 )); then
  sample_failed "vmstat returned $interval_count of 5 interval samples"
fi

busy_avg=$((busy_sum / interval_count))
stamp=$(date +%s)
case $stamp in '' | *[!0-9]*) sample_failed "date did not return an epoch timestamp" ;; esac

temporary=$HEARTBEAT_FILE.$$
printf '%s\n' "$stamp" > "$temporary"
mv -f "$temporary" "$HEARTBEAT_FILE"

pressure=0
if (( busy_avg >= 80 && high_count >= 4 )); then
  pressure=1
  temporary=$PRESSURE_FILE.$$
  printf '%s %s\n' "$stamp" "$busy_avg" > "$temporary"
  mv -f "$temporary" "$PRESSURE_FILE"
else
  rm -f "$PRESSURE_FILE"
fi

top_processes="not captured"
if (( pressure == 1 )); then
  ps_out=$(ps -axr -o pid,ppid,pgid,user,state,pcpu,time 2>/dev/null) || ps_out=""
  p1=""
  p2=""
  p3=""
  process_count=0
  while IFS= read -r row; do
    case $row in PID* | '') continue ;; esac
    process_count=$((process_count + 1))
    case $process_count in
      1) p1=$row ;;
      2) p2=$row ;;
      3) p3=$row; break ;;
    esac
  done <<EOF
$ps_out
EOF
  top_processes="${p1:-none}; ${p2:-none}; ${p3:-none}"
fi

printf '%s busy_pct=%s high_samples=%s/5 cpu_pressure=%s top="%s"\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$busy_avg" "$high_count" "$pressure" "$top_processes" >> "$LOG"

if (( pressure == 1 )); then
  alert_key=cpu-sustained
  (( busy_avg < 95 )) || alert_key=cpu-critical
  "$ALERT_BIN" raise "$alert_key" \
    "five one-second CPU samples averaged ${busy_avg}% busy (${high_count}/5 at or above 80%); top processes: $top_processes"
fi

exit 0
