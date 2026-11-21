#!/usr/bin/env zsh
# _service.sh — rc.d service installation and relayd routing for copy-tree deploy.
# Source this file; do not execute directly. Requires _core.sh sourced first.
set -euo pipefail

# retire_legacy_rails_rcd APP_NAME — stop duplicate *_rails services from older bootstrap.
retire_legacy_rails_rcd() {
  local app_name=$1 legacy="${app_name}_rails"
  [[ -f /etc/rc.d/$legacy ]] || return 0
  [[ -f /etc/rc.d/$legacy && ! -L /etc/rc.d/$legacy ]] || return 0
  "${_PRIV}" /usr/sbin/rcctl disable "$legacy" \
    || { log_err "could not disable legacy service ${legacy}"; return 1; }
  log_ok "disabled legacy rc.d ${legacy} (no stop - shared port with ${app_name})"
}

# assert_rcd_identity — CY15: rc.d daemon_user and APP_DIR must match deploy target.
assert_rcd_identity() {
  local svc=$1 expected_user=$2 expected_dir=$3
  local rcd="/etc/rc.d/${svc}"
  [[ -f $rcd ]] || return 0
  local body; body=$(<"$rcd")
  [[ $body == *"daemon_user=\"${expected_user}\""* ]] || {
    log_err "rc.d ${svc}: daemon_user must be ${expected_user}"
    return 1
  }
  [[ $body == *"daemon_execdir=\"${expected_dir}\""* ]] || {
    log_err "rc.d ${svc}: daemon_execdir must be ${expected_dir}"
    return 1
  }
  log_ok "rc.d ${svc} identity ok (${expected_user} -> ${expected_dir})"
}

# install_rcd APP_NAME APP_DIR PORT SERVICE_NAME
# Service files are installed by the reviewed operator sync, never copied from
# the deploy account's writable checkout during an app deploy.
install_rcd() {
  local app_name=$1 app_dir=$2 port=$3 svc=${4:-$1}
  local rcd_dst="/etc/rc.d/${svc}"
  if [[ ! -f $rcd_dst || -L $rcd_dst ]]; then
    log_err "rc.d ${svc} is missing or symlinked - run the reviewed OPENBSD/OPERATOR.sh sync first"
    return 1
  fi
  local owner mode
  owner=$(/usr/bin/stat -f %u "$rcd_dst") || return 1
  mode=$(/usr/bin/stat -f %Lp "$rcd_dst") || return 1
  [[ $owner == 0 && $mode == 555 ]] || {
    log_err "rc.d ${svc} must be root-owned mode 555; run the reviewed OPENBSD/OPERATOR.sh sync first"
    return 1
  }
  assert_rcd_identity "$svc" "$app_name" "$app_dir"
  retire_legacy_rails_rcd "$app_name"
  log_ok "rc.d ${svc} verified (operator-installed, root-owned, mode 555)"
}

# relayd_confirm_live PORT
# Check the already-running TLS listener during deploy preflight. This does not
# claim the Rails process is ready; post_restart_probe checks the app's own /up
# endpoint after the service restart.
#
# If 443 refuses, checking the app's own port distinguishes a proxy failure from
# an app failure. Port 80 is not useful here: this host's relay listens on 443.
relayd_confirm_live() {
  local app_port=$1
  local deadline=20

  if "$RUBY" -e '
    require "socket"
    port, deadline = ARGV.map(&:to_i)
    deadline.times do
      begin
        Socket.tcp("127.0.0.1", port, connect_timeout: 1) { |s| s.close }
        exit 0
      rescue StandardError
        sleep 1
      end
    end
    exit 1
  ' 443 "$deadline"; then
    log_ok "relayd: 443 accepting during deploy preflight"
    return 0
  fi

  if "$RUBY" -e '
    require "socket"
    begin
      Socket.tcp("127.0.0.1", ARGV[0].to_i, connect_timeout: 1) { |s| s.close }
      exit 0
    rescue StandardError
      exit 1
    end
  ' "$app_port"; then
    log_err "relayd: 443 refused for ${deadline}s while the app still answers on ${app_port} - relayd is down, every site with it"
  else
    log_err "relayd: 443 refused for ${deadline}s and so did ${app_port} - check the app before blaming relayd"
  fi
  return 1
}

# post_restart_probe APP_NAME APP_PORT [MAX_TRIES]
# Prove the Rails process answers its own liveness endpoint after rcctl restart.
# Falcon can take longer than one connection timeout to boot, so retry boundedly.
post_restart_probe() {
  local app_name=$1 app_port=$2 max_tries=${3:-12}
  local attempt=1

  while (( attempt <= max_tries )); do
    if curl -fsS -m 10 -o /dev/null "http://127.0.0.1:${app_port}/up" 2>/dev/null; then
      log_ok "${app_name}: /up answering on :${app_port} after ${attempt} attempt(s)"
      return 0
    fi
    if (( attempt < max_tries )); then
      sleep 5
    fi
    attempt=$(( attempt + 1 ))
  done

  log_err "${app_name}: /up never answered on :${app_port} after ${max_tries} attempts"
  return 1
}

# relayd_add_relay APP_NAME DOMAIN PORT
# Read-only check against the installed root-owned relayd policy. New Host
# routes remain a deliberate OPENBSD/mirror/etc/relayd.conf change.
relayd_add_relay() {
  local app=$1 domain=$2 port=$3

  case "$app" in brgen|amber|bsdports|mrdamascy) ;; *) log_err "relayd: refused unknown app: $app"; return 2 ;; esac
  [[ $domain == *.* ]] || { log_err "relayd: refused invalid domain"; return 2; }
  [[ $port == <-> && $port -ge 1 && $port -le 65535 ]] || { log_err "relayd: refused invalid port"; return 2; }

  "$RUBY" -e '
    require "etc"
    app, domain, requested_port = ARGV
    path = "/etc/relayd.conf"
    stat = File.lstat(path)
    abort "relayd.conf must be a root-owned, non-writable regular file" unless
      stat.file? && !stat.symlink? && stat.uid.zero? && (stat.mode & 0o022).zero?
    source = File.read(path, encoding: "UTF-8")
    abort "invalid domain" unless domain.match?(/\A[a-z0-9](?:[a-z0-9.-]{0,251}[a-z0-9])?\z/) && !domain.include?("..")
    abort "no TLS keypair for #{domain}" unless source.match?(/^\s*tls keypair "#{Regexp.escape(domain)}"\s*$/)
    abort "no relay table for #{app}" unless source.match?(/^\s*table <#{Regexp.escape(app)}>\s*\{/)
    ports = source.scan(/^\s*forward to <#{Regexp.escape(app)}> port ([0-9]+) check http "\/up" code 200\s*$/).flatten.uniq
    abort "no unique root-configured backend port for #{app}" unless ports.length == 1
    abort "configured port differs from #{requested_port}" unless ports.first == requested_port
    start = source.index(%(http protocol "https_proxy" {))
    abort "https_proxy protocol block is missing" unless start
    finish = source.index("\n}", start)
    abort "https_proxy protocol block is unterminated" unless finish
    protocol = source[start..finish]
    pattern = /^\s*match request header "Host" value "#{Regexp.escape(domain)}" forward to <([a-z0-9_]+)>\s*$/
    routes = protocol.lines.filter_map { |line| (match = line.match(pattern)) && match[1] }.uniq
    abort "no approved Host route for #{domain}" if routes.empty?
    abort "#{domain} routes to #{routes.join(", ")}, not #{app}" unless routes == [app]
    puts "relayd route verified: #{domain} -> #{app}:#{requested_port}"
  ' "$app" "$domain" "$port" || {
    log_err "relayd: root-approved route check failed for ${domain}"
    return 1
  }
  relayd_confirm_live "$port" || return 1
  log_ok "relayd: ${domain} verified for ${app}:${port}"
  return 0
}

# warm_brgen_after_restart — Falcon cold boot can exceed relayd/client timeouts
warm_brgen_after_restart() {
  local port=${1:-38182}
  sleep 8
  curl -fsS -m 120 -H "Host: brgen.no" "http://127.0.0.1:${port}/up" -o /dev/null 2>/dev/null \
    || log_warn "brgen warm /up skipped"
  curl -fsS -m 120 -H "Host: markedsplass.brgen.no" "http://127.0.0.1:${port}/" -o /dev/null 2>/dev/null \
    || log_warn "brgen warm marketplace skipped"
}
