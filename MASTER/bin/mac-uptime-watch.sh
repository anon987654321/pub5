#!/bin/zsh
# mac-uptime-watch -- external public-service and vm23 CPU monitoring.
#
# One invocation is one tick. State persists under ~/.pub5; launchd or cron
# may call this every five minutes. Curl and SSH probes are bounded; stale
# locks are recovered only after the owning process is confirmed gone.

umask 077

: ${PUB5_UPTIME_HOSTS:="brgen.no amberapp.no ai.brgen.no bsdports.org"}
: ${PUB5_UPTIME_WAIVED:="bsdports.org"}
: ${PUB5_UPTIME_FAILS:=3}
: ${PUB5_VM23_SSH_HOST:="dev@brgen.no"}
: ${PUB5_VM23_SSH_KEY:="$HOME/.ssh/id_ed25519_brgen"}
: ${PUB5_VM23_CPU_WARN:=80}
: ${PUB5_VM23_CPU_CRIT:=95}
: ${PUB5_VM23_CPU_RECOVER:=60}
: ${PUB5_VM23_CPU_WARN_SAMPLES:=3}
: ${PUB5_VM23_CPU_CRIT_SAMPLES:=2}
: ${PUB5_VM23_CPU_RECOVER_SAMPLES:=3}
: ${PUB5_VM23_SSH_FAILS:=2}

STATE="$HOME/.pub5/uptime_watch.state"
CPU_STATE="$HOME/.pub5/vm23_cpu.state"
CPU_LOG="$HOME/.pub5/vm23_cpu.log"
LOCKDIR="$HOME/.pub5/uptime_watch.lock"
STALE_LOCK_AGE=30
LOCK_OWNED=0
STATE_TMP=""
SCRIPT_NAME=${0:t}

mkdir -p "$HOME/.pub5" 2>/dev/null || exit 1

lock_appears_live() {
  local owner process_command lock_mtime current
  owner=""
  [[ -r "$LOCKDIR/pid" ]] && owner=$(<"$LOCKDIR/pid")

  if [[ "$owner" == <-> ]] && kill -0 "$owner" 2>/dev/null; then
    process_command=$(ps -p "$owner" -o command= 2>/dev/null)
    [[ "$process_command" == *"$SCRIPT_NAME"* ]] && return 0
  fi

  # A creator may be between mkdir and writing pid. Give it a short grace
  # period; after that, an absent or dead owner is safe to reap. The mtime
  # reader follows the host's stat: BSD -f on macOS, GNU -c on Linux.
  lock_mtime=$(stat -f %m "$LOCKDIR" 2>/dev/null)
  [[ "$lock_mtime" == <-> ]] || lock_mtime=$(stat -c %Y "$LOCKDIR" 2>/dev/null)
  [[ "$lock_mtime" == <-> ]] || return 0
  current=$(date +%s)
  (( current - lock_mtime < STALE_LOCK_AGE ))
}

acquire_lock() {
  local attempt
  for attempt in 1 2 3; do
    if mkdir "$LOCKDIR" 2>/dev/null; then
      if print -r -- "$$" > "$LOCKDIR/pid"; then
        LOCK_OWNED=1
        return 0
      fi
      rmdir "$LOCKDIR" 2>/dev/null
      return 1
    fi

    lock_appears_live && return 1
    [[ -f "$LOCKDIR/pid" ]] && rm -f "$LOCKDIR/pid"
    rmdir "$LOCKDIR" 2>/dev/null || return 1
  done
  return 1
}

cleanup() {
  [[ -n "$STATE_TMP" ]] && rm -f "$STATE_TMP"
  if (( LOCK_OWNED )) && [[ -r "$LOCKDIR/pid" ]] && [[ "$(<"$LOCKDIR/pid")" == "$$" ]]; then
    rm -f "$LOCKDIR/pid"
    rmdir "$LOCKDIR" 2>/dev/null
  fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

acquire_lock || exit 0

typeset -A previous_failures
if [[ -r "$STATE" ]]; then
  while IFS=' ' read -r host previous_code previous_count; do
    [[ -n "$host" && "$previous_count" == <-> ]] || continue
    previous_failures[$host]="$previous_count"
  done < "$STATE"
fi

STATE_TMP="$STATE.new.$"
: > "$STATE_TMP" || exit 1
alerted=0

vm23_cpu_notice() {
  local kind=$1 message=$2
  print -r -- "$(date '+%Y-%m-%d %H:%M:%S') $kind $message" >> "$CPU_LOG"
  osascript -e "display notification \"$message\" with title \"pub5 vm23 CPU\" sound name \"Basso\"" >/dev/null 2>&1 || true
  alerted=1
}

vm23_cpu_sample() {
  local output line a b c rows=0 samples=0 user_sum=0 system_sum=0 idle_sum=0
  typeset -a ssh_opts columns
  ssh_opts=(
    -o BatchMode=yes
    -o StrictHostKeyChecking=accept-new
    -o ConnectTimeout=5
    -o ServerAliveInterval=2
    -o ServerAliveCountMax=2
  )
  [[ -f "$PUB5_VM23_SSH_KEY" ]] && ssh_opts+=(-i "$PUB5_VM23_SSH_KEY")
  output=$(ssh "${ssh_opts[@]}" "$PUB5_VM23_SSH_HOST" "/usr/bin/vmstat -c 6 -w 1" 2>/dev/null) || return 1

  while IFS= read -r line; do
    columns=(${=line})
    (( ${#columns} >= 3 )) || continue
    a=${columns[-3]}
    b=${columns[-2]}
    c=${columns[-1]}
    [[ $a == <-> && $b == <-> && $c == <-> ]] || continue
    if (( rows == 0 )); then
      rows=1
      continue
    fi
    user_sum=$(( user_sum + 10#$a ))
    system_sum=$(( system_sum + 10#$b ))
    idle_sum=$(( idle_sum + 10#$c ))
    samples=$(( samples + 1 ))
  done <<< "$output"

  (( samples == 5 )) || return 1
  print -r -- $(( (user_sum + system_sum) / samples ))
}

watch_vm23_cpu() {
  local state=clear high=0 critical=0 recovery=0 sshfails=0 sshdown=0
  local previous busy sample tmp
  if [[ -r "$CPU_STATE" ]]; then
    read state high critical recovery sshfails sshdown < "$CPU_STATE"
  fi
  case $state in clear|warning|critical) ;; *) state=clear ;; esac
  [[ $high == <-> ]] || high=0
  [[ $critical == <-> ]] || critical=0
  [[ $recovery == <-> ]] || recovery=0
  [[ $sshfails == <-> ]] || sshfails=0
  [[ $sshdown == <-> ]] || sshdown=0
  previous=$state

  sample=$(vm23_cpu_sample) || {
    sshfails=$(( sshfails + 1 ))
    print -r -- "$(date '+%Y-%m-%d %H:%M:%S') PROBE-FAILED ssh=$sshfails" >> "$CPU_LOG"
    if (( sshfails >= PUB5_VM23_SSH_FAILS && sshdown == 0 )); then
      vm23_cpu_notice "UNREACHABLE" "vm23 CPU probe via SSH failed for $sshfails consecutive checks"
      sshdown=1
    fi
    tmp="${CPU_STATE}.new"
    print -r -- "$state $high $critical $recovery $sshfails $sshdown" > "$tmp" &&
      mv -f "$tmp" "$CPU_STATE" || { rm -f "$tmp"; alerted=1; }
    return 0
  }

  busy=$sample
  sshfails=0
  if (( sshdown )); then
    vm23_cpu_notice "SSH-RECOVERED" "vm23 CPU probe via SSH is reachable again"
    sshdown=0
  fi

  if (( busy >= PUB5_VM23_CPU_WARN )); then high=$(( high + 1 )); else high=0; fi
  if (( busy >= PUB5_VM23_CPU_CRIT )); then critical=$(( critical + 1 )); else critical=0; fi

  if [[ $state == clear ]]; then
    if (( critical >= PUB5_VM23_CPU_CRIT_SAMPLES )); then
      state=critical
    elif (( high >= PUB5_VM23_CPU_WARN_SAMPLES )); then
      state=warning
    fi
  else
    if (( busy < PUB5_VM23_CPU_RECOVER )); then
      recovery=$(( recovery + 1 ))
      if (( recovery >= PUB5_VM23_CPU_RECOVER_SAMPLES )); then
        state=clear
        high=0
        critical=0
        recovery=0
      fi
    else
      recovery=0
      if (( critical >= PUB5_VM23_CPU_CRIT_SAMPLES )); then state=critical; fi
    fi
  fi

  print -r -- "$(date '+%Y-%m-%d %H:%M:%S') busy=${busy}% state=$state" >> "$CPU_LOG"
  tmp="${CPU_STATE}.new"
  print -r -- "$state $high $critical $recovery $sshfails $sshdown" > "$tmp" &&
    mv -f "$tmp" "$CPU_STATE" || { rm -f "$tmp"; alerted=1; return 1; }

  if [[ $previous == clear && $state == warning ]]; then
    vm23_cpu_notice "SATURATED" "vm23 CPU busy ${busy}% for $high five-minute checks (limit $PUB5_VM23_CPU_WARN%)"
  elif [[ $previous != critical && $state == critical ]]; then
    vm23_cpu_notice "CRITICAL" "vm23 CPU busy ${busy}% for $critical five-minute checks (limit $PUB5_VM23_CPU_CRIT%)"
  elif [[ $previous != clear && $state == clear ]]; then
    vm23_cpu_notice "RECOVERED" "vm23 CPU recovered to ${busy}% for $PUB5_VM23_CPU_RECOVER_SAMPLES checks"
  fi
}


for host in ${(z)PUB5_UPTIME_HOSTS}; do
  if [[ " ${PUB5_UPTIME_WAIVED} " == *" $host "* ]]; then
    continue
  fi

  code=$(curl -sS -m 10 -o /dev/null -w '%{http_code}' "https://$host/up" 2>/dev/null)
  [[ -z "$code" ]] && code=000

  previous=${previous_failures[$host]:-0}
  if [[ "$code" == "200" ]]; then
    if (( previous >= PUB5_UPTIME_FAILS )); then
      print -r -- "RECOVERED $host $(date '+%Y-%m-%d %H:%M:%S')" >> "$HOME/.pub5/uptime_watch.log"
      osascript -e "display notification \"$host /up is answering again\" with title \"pub5 uptime\"" >/dev/null 2>&1 || true
    fi
    print -r -- "$host 0 0" >> "$STATE_TMP"
  else
    fails=$(( previous + 1 ))
    print -r -- "$host $code $fails" >> "$STATE_TMP"
    if (( fails >= PUB5_UPTIME_FAILS )); then
      alerted=1
      if (( previous < PUB5_UPTIME_FAILS )); then
        print -r -- "DOWN $host code=$code ticks=$fails $(date '+%Y-%m-%d %H:%M:%S')" >> "$HOME/.pub5/uptime_watch.log"
        osascript -e "display notification \"$host /up down (HTTP $code, $fails ticks)\" with title \"pub5 uptime\" sound name \"Basso\"" >/dev/null 2>&1 || true
      fi
    fi
  fi
done

watch_vm23_cpu

mv -f "$STATE_TMP" "$STATE" || exit 1
STATE_TMP=""
(( alerted )) && exit 1
exit 0
