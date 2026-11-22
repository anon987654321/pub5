#!/usr/bin/env zsh
# _core.sh — privilege detection, logging, and the one command-existence
# check every other _*.sh file in this directory depends on.
# Source this file; do not execute directly.
set -euo pipefail

PATH="${PATH:-/usr/local/bin:/usr/bin:/bin}"

if command -v doas >/dev/null 2>&1; then
  _PRIV=doas
else
  _PRIV=sudo
fi

: "${APP_PORT:=3000}"

log()      { print -P "%F{cyan}==>%f $*"; }
log_ok()   { print -P "%F{green}ok%f $*"; }
log_warn() { print -P "%F{yellow}WARN%f $*" >&2; }
log_err()  { print -P "%F{red}ERR%f $*" >&2; }

need_cmd() {
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null 2>&1 || { log_err "Required: $cmd"; exit 1; }
    log_ok "$cmd found"
  done
}

# Native OpenBSD service control. Keep the action and service vocabulary
# closed here; doas supplies root only for rcctl itself.
pub4_rcctl() {
  local action=${1:-} service=${2:-}
  case "$action" in
    check|get|start|stop|restart) ;;
    *) log_err "pub4_rcctl: refused action: $action"; return 2 ;;
  esac
  case "$service" in
    master|brgen|amber|bsdports|mrdamascy|master_jobs|brgen_jobs|amber_jobs|bsdports_jobs) ;;
    *) log_err "pub4_rcctl: refused service: $service"; return 2 ;;
  esac
  "${_PRIV}" /usr/sbin/rcctl "$action" "$service"
}

# deploy_status APP_NAME STEP [STATE] — single source of truth for "is a
# deploy running right now and what step is it on." Before this, the only way
# to tell a live deploy apart from a hung/crashed process was ps/rcctl
# archaeology (grepping for db:schema:load, bin/ci, etc. and guessing from
# elapsed CPU time). STATE defaults to "running"; pass "done" or "failed" to
# close out the run. One file per app (not one shared file) so concurrent
# deploys of different apps don't clobber each other's state.
# Records live under /var/db/pub5/deploy_status as root:wheel 0640 files
# in a root:wheel 0750 directory. dev is in wheel, so vps-state can read the
# evidence directly; no privileged read API is needed.
DEPLOY_STATUS_DIR=/var/db/pub5/deploy_status
deploy_status() {
  local app=$1 step=$2 state=${3:-running}
  local now pid
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  DEPLOY_STATUS_STARTED_AT=${DEPLOY_STATUS_STARTED_AT:-$now}
  pid="${$}"

  ${_PRIV} "$RUBY" -rjson -retc -rtime -rsecurerandom -rfileutils -e '
    app, step, state, pid, started_at = ARGV
    abort "invalid app identifier" unless app.match?(/\A[a-z][a-z0-9_]{0,31}\z/)
    abort "invalid deploy state" unless %w[running done failed].include?(state)
    abort "invalid deploy step" unless step.bytesize.between?(1, 160) && step.match?(/\A[A-Za-z0-9_ .:+(),\/-]+\z/)
    root = "/var/db/pub5"
    directory = File.join(root, "deploy_status")
    ["/var/db", root].each do |path|
      raise "#{path} is a symlink" if File.symlink?(path)
      next unless File.exist?(path)
      stat = File.lstat(path)
      raise "#{path} must be a root-owned directory" unless stat.directory? && stat.uid.zero?
    end
    FileUtils.mkdir_p(directory, mode: 0o750)
    wheel = Etc.getgrnam("wheel").gid
    File.chown(0, wheel, root)
    File.chmod(0o755, root)
    stat = File.lstat(directory)
    raise "#{directory} must be a real root-owned directory" unless stat.directory? && !stat.symlink? && stat.uid.zero?
    File.chown(0, wheel, directory)
    File.chmod(0o750, directory)
    target = File.join(directory, "#{app}.json")
    raise "#{target} is a symlink" if File.symlink?(target)
    previous = nil
    if File.exist?(target)
      old = File.lstat(target)
      raise "#{target} must be a root-owned regular file" unless old.file? && old.uid.zero?
      previous = JSON.parse(File.read(target))
    end
    now = Time.now.utc.iso8601
    payload = {
      app: app, step: step, state: state, pid: Integer(pid, 10),
      started_at: previous && previous["state"] == "running" ? previous["started_at"] : started_at,
      updated_at: now
    }
    temporary = File.join(directory, ".#{app}.#{Process.pid}.#{SecureRandom.hex(6)}")
    begin
      File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
        file.write(JSON.generate(payload) + "\n")
        file.flush
        file.fsync
      end
      File.chown(0, wheel, temporary)
      File.chmod(0o640, temporary)
      File.rename(temporary, target)
    ensure
      File.unlink(temporary) if File.exist?(temporary)
    end
    puts "deploy_status0: #{app} #{state} step=#{step}"
  ' "$app" "$step" "$state" "$pid" "$DEPLOY_STATUS_STARTED_AT" || {
    log_warn "deploy_status: direct atomic write failed for ${app}/${step}"
    return 0
  }
}
