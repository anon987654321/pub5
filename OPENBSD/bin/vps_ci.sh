#!/usr/bin/env zsh
# Verify workstation CI attestation and the preinstalled production bundle for one Rails app on vm23.
# Usage: zsh OPENBSD/bin/vps_ci.sh APP (internal child of the pinned vps-deploy flow)
set -euo pipefail

usage="usage: zsh OPENBSD/bin/vps_ci.sh APP - require pinned parent proofs, sync APP's copy-tree, then check the read-only production bundle"
if [[ ${1:-} == -h || ${1:-} == --help ]]; then
  print -r -- "$usage"
  exit 0
fi

app=${1:-}
[[ -n $app ]] || { print -u2 -r -- "$usage"; exit 2 }

# Validate before using the argument in any filesystem path. This deployment
# child accepts only registered Rails apps and cannot widen its filesystem reach.
case $app in
  brgen|amber|bsdports|mrdamascy) ;;
  *) print -u2 "vps_ci: unknown app \"$app\" - allowed: brgen, amber, bsdports, mrdamascy"; exit 2 ;;
esac

repo=${PUB5_ROOT:-/home/dev/pub5}
deploy_user=${VPS_DEPLOY_USER:-dev}
[[ $deploy_user == [a-z]* && $deploy_user != *[^a-z0-9_]* ]] || {
  print -u2 "vps_ci: refused - invalid deploy-user identifier"
  exit 2
}

# Git reads the dev-owned checkout as its owner. This helper runs as root for
# service orchestration; never invoke Git as root or create root-owned repo files.
run_as_deploy_user() {
  local snippet=$1
  /usr/bin/su -s /bin/sh "$deploy_user" -c "$snippet"
}
git_as_deploy_user() {
  local args_q
  args_q=$(printf '%q ' "$@")
  run_as_deploy_user "cd $(printf '%q' "$repo") && git $args_q"
}

# This helper is an internal child of a pinned, admitted release. Verify the
# parent's live lock record and process identity; an environment flag alone
# must never authorize a production copy-tree mutation.
lock_dir=${VPS_DEPLOY_LOCK_DIR:-${VPS_DEPLOY_HOME:-/home/$deploy_user}/.pub5-vps-deploy.lock}
[[ ${VPS_DEPLOY_LOCK_HELD:-} == 1 && ${VPS_DEPLOY_LOCK_PID:-} == <-> && -n ${VPS_DEPLOY_LOCK_IDENTITY:-} ]] || {
  print -u2 "vps_ci: refused - no inherited parent deployment lock"
  exit 75
}
[[ -d $lock_dir && ! -L $lock_dir && -f $lock_dir/owner && ! -L $lock_dir/owner ]] || {
  print -u2 "vps_ci: refused - parent deployment lock record is missing or unsafe"
  exit 75
}
read -r owner_pid owner_host owner_epoch owner_identity < "$lock_dir/owner" || {
  print -u2 "vps_ci: refused - cannot read parent deployment lock record"
  exit 75
}
[[ $owner_pid == "$VPS_DEPLOY_LOCK_PID" && $owner_host == "$(hostname -s)" &&
   $owner_epoch == <-> && $owner_identity == "$VPS_DEPLOY_LOCK_IDENTITY" ]] || {
  print -u2 "vps_ci: refused - parent lock record does not match the inherited identity"
  exit 75
}
owner_started=$(LC_ALL=C ps -p "$owner_pid" -o lstart= 2>/dev/null) || {
  print -u2 "vps_ci: refused - cannot read parent process start time"
  exit 75
}
owner_command=$(ps -ww -p "$owner_pid" -o command= 2>/dev/null) || {
  print -u2 "vps_ci: refused - cannot read parent process command"
  exit 75
}
[[ -n $owner_started && -n $owner_command ]] || {
  print -u2 "vps_ci: refused - parent process identity is unavailable"
  exit 75
}
owner_started=${owner_started//[^A-Za-z0-9]/_}
owner_digest=$(print -rn -- "$owner_command" | cksum) || {
  print -u2 "vps_ci: refused - cannot fingerprint parent process"
  exit 75
}
owner_digest=${owner_digest// /_}
[[ ${owner_started}_${owner_digest} == "$owner_identity" ]] || {
  print -u2 "vps_ci: refused - parent deployment process identity changed"
  exit 75
}

# Verify every workstation proof before the first permission change or sync.
head=$(git_as_deploy_user rev-parse HEAD 2>/dev/null) || {
  print -u2 "vps_ci: refused - cannot read the checkout HEAD"
  exit 1
}
[[ ${VPS_DEPLOY_SHA:-} == "$head" ]] || {
  print -u2 "vps_ci: refused - no matching pinned deployment SHA for $head"
  exit 1
}
attested=${VPS_DEPLOY_CI_SHA:-}
[[ $attested == "$head" ]] || {
  print -u2 "vps_ci: refused - no matching workstation CI attestation for $head; no sync was started"
  exit 1
}
[[ ${VPS_DEPLOY_ADMITTED_SHA:-} == "$head" ]] || {
  print -u2 "vps_ci: refused - no matching parent host-admission token for $head; no sync was started"
  exit 1
}
if [[ -n ${VPS_DEPLOY_PREFLIGHT_SHA:-} ]]; then
  [[ $VPS_DEPLOY_PREFLIGHT_SHA == "$head" ]] || {
    print -u2 "vps_ci: refused - workstation preflight SHA does not match $head; no sync was started"
    exit 1
  }
else
  [[ ${VPS_DEPLOY_SKIP_PREFLIGHT:-0} == 1 && ${I_UNDERSTAND_FAST_DEPLOY:-0} == 1 ]] || {
    print -u2 "vps_ci: refused - no matching workstation preflight for $head; no sync was started"
    exit 1
  }
fi

app_dir=/home/${app}/app
# The Gemfiles name path gems relative to the app dir (../__shared, engines/*),
# so the copy-tree keeps them as siblings of app/, the layout RAILS/_deploy.sh builds.
[[ -d $app_dir ]] || { print -u2 "missing $app_dir"; exit 1 }


# deploy_status (from RAILS/_core.sh) records this app's active release stage.
# `bin/vps-state` reads the same per-app progress record.
[[ -f ${repo}/RAILS/_core.sh ]] && . "${repo}/RAILS/_core.sh"
command -v deploy_status >/dev/null 2>&1 || deploy_status() { :; }

export PUB5_CI_GUARD=1
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
  tracked=(${(f)"$(git_as_deploy_user ls-files "RAILS/$app" 2>/dev/null)"}) || return 0
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
    # aborted every deployment sync step with "synced[(r)$top/*]: parameter not set"
    # — the guard erroring rather than the thing it guards.
    [[ -n ${synced[(r)$top/*]:-} ]] && continue
    (( ${kept[(Ie)$top]} )) && continue
    [[ $top == *.sh || $top == *.md ]] && continue
    missing+=($top)
  done

  local -a uniq_missing=(${(u)missing})
  (( ${#uniq_missing} )) || return 0
  print -u2 "vps_ci: $app - tracked but neither synced nor kept local: ${uniq_missing}"
  print -u2 "vps_ci: $app - account for each path used by the deployed app or add it to kept_local with a reason"
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

print "vps_ci: $app (bounded sync + read-only bundle check)"
# The parent owns deployment serialization; prepare app permissions before the
# app-owned synchronizer updates the production copy-tree.
pub5_ensure_ci_lock >/dev/null
doas /usr/local/libexec/ci-prepare.ksh "$app"
deploy_status "$app" "sync tree"
sync_from_repo

# Every selected Rails app runs bin/ci on the workstation before SSH.
# vm23 verifies the attestation against this checkout and performs a read-only
# check of the preinstalled OpenBSD/Ruby production bundle.
. "${repo}/RAILS/_runtime_check.sh"
deploy_status "$app" "bundle check"
run_rails_as_app "$app" "$app_dir" "bundle-check" || {
  # A lockfile bump must not end the deploy when the box already holds the
  # same-version built gems under another application. Borrow them, fill
  # the rest with one bounded, niced install, and only then re-judge.
  # Proven by hand for brgen and mrdamascy on 2026-11-25.
  deploy_status "$app" "bundle hydrate"
  if ! run_rails_as_app "$app" "$app_dir" "bundle-sibling-hydrate"; then
    print -u2 "vps_ci: $app sibling-bundle hydration failed; build the matching OpenBSD bundle off-host"
    exit 1
  fi
  deploy_status "$app" "bundle install"
  if ! run_rails_as_app "$app" "$app_dir" "bundle-install"; then
    print -u2 "vps_ci: $app bounded bundle install did not complete; see the still-missing list above"
    exit 1
  fi
  deploy_status "$app" "bundle check"
  run_rails_as_app "$app" "$app_dir" "bundle-check" || {
    deploy_status "$app" "bundle check" "failed"
    print -u2 "vps_ci: $app production bundle is still incomplete after hydration"
    print -u2 "vps_ci: $app and a bounded install; build the matching OpenBSD bundle off-host"
    exit 1
  }
}
print "vps_ci: $app workstation CI attestation matches; production bundle is present"
ci_stamp=ci_attested

sha=$(git_as_deploy_user rev-parse --short HEAD 2>/dev/null || echo unknown)
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
