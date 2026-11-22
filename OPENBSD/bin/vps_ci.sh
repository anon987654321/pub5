#!/usr/bin/env zsh
# Run one Rails app CI on vm23 with mutex + load check (serial operator entrypoint).
# Usage: zsh OPENBSD/bin/vps_ci.sh brgen
set -euo pipefail

usage="usage: zsh OPENBSD/bin/vps_ci.sh APP - sync APP's copy-tree, then run its bin/ci under the CI lock"
if [[ ${1:-} == -h || ${1:-} == --help ]]; then
  print -r -- "$usage"
  exit 0
fi

app=${1:-}
[[ -n $app ]] || { print -u2 -r -- "$usage"; exit 2 }

# Validate before using the argument in any filesystem path. This entrypoint
# only runs Rails app CI; an arbitrary app string must never widen its reach.
case $app in
  brgen|amber|bsdports|mrdamascy) ;;
  *) print -u2 "vps_ci: unknown app \"$app\" - allowed: brgen, amber, bsdports, mrdamascy"; exit 2 ;;
esac

repo=${PUB5_ROOT:-/home/dev/pub5}
app_dir=/home/${app}/app
# The Gemfiles name path gems relative to the app dir (../__shared, engines/*),
# so the copy-tree keeps them as siblings of app/, the layout RAILS/_deploy.sh builds.
[[ -d $app_dir ]] || { print -u2 "missing $app_dir"; exit 1 }


# deploy_status (from RAILS/_core.sh) -- same in-progress status file the
# SKIP_CI=1 path (_deploy.sh/_runtime_check.sh) writes, so `bin/vps-state`
# is one place to check regardless of which deploy path is running.
[[ -f ${repo}/RAILS/_core.sh ]] && . "${repo}/RAILS/_core.sh"
command -v deploy_status >/dev/null 2>&1 || deploy_status() { :; }

export PUB4_CI_GUARD=1
export PUB5_RAILS_ROOT=${PUB5_RAILS_ROOT:-$repo/RAILS}

# Path and safe creation live in OPENBSD/lib/ci_lock.sh — the lock moved out of
# world-writable /var/tmp, where root was chmod'ing a caller-chosen, symlinkable path.
. "${repo}/OPENBSD/lib/ci_lock.sh"

# Names every tracked entry at the app root that is neither synced nor kept
# local. Warns rather than fails: this list is discovered from git at deploy
# time, so a wrong reading here would refuse a deploy for a documentation file,
# and a deploy pipeline that cries wolf gets its checks removed. Loud and
# specific is the useful setting until the set has been stable a while.
#
# Found this way: .rubocop.yml was missing and nothing said so for twelve days,
# and .ruby-version is absent from amber's and bsdports' copy-trees entirely.
unaccounted_tracked_files() {
  local app=$1 repo=$2
  local -a synced=(${(P)3}) kept=(${(P)4})
  local -a tracked missing
  tracked=(${(f)"$(git -C "$repo" ls-files "RAILS/$app" 2>/dev/null)"}) || return 0
  (( ${#tracked} )) || return 0

  local rel top
  for rel in $tracked; do
    top=${${rel#RAILS/$app/}%%/*}
    [[ -n $top ]] || continue
    # A synced entry may be a subpath — vendor/javascript covers vendor's only
    # tracked content — so a top-level name counts as accounted when any synced
    # path is it or descends from it. Without this the check reports `vendor`,
    # which is the accounting being wrong rather than the sync.
    (( ${synced[(Ie)$top]} )) && continue
    # :- is load-bearing under `set -u`. (I) yields an index and is 0 when there
    # is no match, so it is safe bare; (r) yields the matched VALUE, and a search
    # that matches nothing is an unset parameter, which nounset makes fatal. This
    # aborted every deploy's CI step with "synced[(r)$top/*]: parameter not set"
    # — the guard erroring rather than the thing it guards.
    [[ -n ${synced[(r)$top/*]:-} ]] && continue
    (( ${kept[(Ie)$top]} )) && continue
    [[ $top == *.sh || $top == *.md ]] && continue
    missing+=($top)
  done

  local -a uniq_missing=(${(u)missing})
  (( ${#uniq_missing} )) || return 0
  print -u2 "vps_ci: $app - tracked but neither synced nor kept local: ${uniq_missing}"
  print -u2 "vps_ci: $app - add each to paths (bin/ci reads the copy-tree) or to kept_local with a reason"
}

# The installed synchronizer is purpose-built and runs as the selected app
# user. doas supplies root only for the su transition; the helper never mutates
# another app's tree.
sync_from_repo() {
  local -a paths=(test app lib config bin db engines public vendor/javascript
                  Gemfile Gemfile.lock config.ru Rakefile .rubocop.yml .ruby-version)
  local -a kept_local=(log storage docs script domains.yml Procfile.dev)
  unaccounted_tracked_files "$app" "$repo" paths kept_local
  doas /usr/bin/su -m "$app" -c "/usr/local/libexec/ci-sync.ksh $app"
}

print "vps_ci: $app (sync + mutex + load check)"
# Establish group access and the private-storage mode before the app-owned
# synchronizer reads the checkout and updates the CI copy-tree.
pub5_ensure_ci_lock >/dev/null
doas /usr/local/libexec/ci-prepare.ksh "$app"
deploy_status "$app" "sync tree"
sync_from_repo

# Every selected Rails app runs bin/ci on the workstation before SSH.
# vm23 verifies the attestation against this checkout and performs a read-only
# check of the preinstalled OpenBSD/Ruby production bundle.
attested=${VPS_DEPLOY_CI_SHA:-}
head=$(git -C "$repo" rev-parse HEAD)
[[ $attested == "$head" ]] || {
  print -u2 "vps_ci: refused - no matching workstation CI attestation for $head; host-side tests and installs are forbidden"
  exit 1
}
. "${repo}/RAILS/_runtime_check.sh"
deploy_status "$app" "bundle check"
run_rails_as_app "$app" "$app_dir" "bundle-check" || {
  deploy_status "$app" "bundle check" "failed"
  print -u2 "vps_ci: $app production bundle is incomplete; build the matching OpenBSD bundle off-host"
  exit 1
}
print "vps_ci: $app CI attested locally; production bundle already present"
ci_stamp=ci_attested

sha=$(git -C "$repo" rev-parse --short HEAD 2>/dev/null || echo unknown)
# This stamp records that bin/ci passed on the workstation for the pinned SHA.
doas "$RUBY" -rjson -retc -rtime -rsecurerandom -rfileutils -rsocket -e '
  app, sha, status = ARGV
  abort "invalid app" unless app.match?(/\A[a-z][a-z0-9_]{0,31}\z/)
  abort "invalid SHA" unless sha == "unknown" || sha.match?(/\A[0-9a-f]{7,40}\z/i)
  abort "invalid CI status" unless status == "ci_attested"
  root = "/var/db/pub5"
  raise "unsafe /var/db/pub5" if File.symlink?(root)
  FileUtils.mkdir_p(root, mode: 0o755)
  wheel = Etc.getgrnam("wheel").gid
  File.chown(0, wheel, root)
  File.chmod(0o755, root)
  target = File.join(root, "last_deploy_#{app}.json")
  raise "stamp path is a symlink" if File.symlink?(target)
  payload = { app: app, sha: sha, at: Time.now.utc.iso8601, status: status, host: Socket.gethostname }
  temporary = File.join(root, ".last_deploy_#{app}.#{Process.pid}.#{SecureRandom.hex(6)}")
  begin
    File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, 0o600) { |file| file.write(JSON.generate(payload) + "\\n"); file.flush; file.fsync }
    File.chown(0, wheel, temporary)
    File.chmod(0o640, temporary)
    File.rename(temporary, target)
  ensure
    File.unlink(temporary) if File.exist?(temporary)
  end
' "$app" "$sha" "$ci_stamp"
deploy_status "$app" "done" "done"
