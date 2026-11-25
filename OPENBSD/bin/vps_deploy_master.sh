#!/usr/bin/env zsh
# Run with zsh, as vps-deploy does: the runtime-dirs step uses zsh globs (tmp/**/*(/N)),
# which a POSIX sh refuses to parse.
# Deploy prebuilt MASTER web + lib as a child of the pinned vps-deploy flow.
#
# This is the body of `bin/vps-deploy master`, which also writes the deploy
# stamp; run that. Calling this file directly deploys without a stamp, which
# is only right when vps-deploy itself is what is broken.
#
# Internal child only: invoke through OPENBSD/bin/vps-deploy.

set -eo pipefail
# SSH and direct invocation use a non-login shell; pin the OpenBSD package path.
export PATH=/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin
ROOT="${ROOT:-/home/dev/pub5}"
if [ "$ROOT" != "/home/dev/pub5" ]; then
  echo "vps_deploy_master: ROOT override refused; this deployer mutates the fixed /home/dev/pub5/MASTER/web tree" >&2
  exit 2
fi
. "$ROOT/OPENBSD/lib/ruby_select.sh"
WEB="$ROOT/MASTER/web"

# This is an internal child, not a standalone deployment command. Verify the
# live parent lock and process fingerprint before reading or changing production.
deploy_user="${VPS_DEPLOY_USER:-dev}"
[[ $deploy_user == [a-z]* && $deploy_user != *[^a-z0-9_]* ]] || {
  echo "vps_deploy_master: invalid deploy-user identifier" >&2
  exit 2
}
lock_dir=${VPS_DEPLOY_LOCK_DIR:-${VPS_DEPLOY_HOME:-/home/$deploy_user}/.pub5-vps-deploy.lock}
[[ ${VPS_DEPLOY_LOCK_HELD:-} == 1 && ${VPS_DEPLOY_LOCK_PID:-} == <-> && -n ${VPS_DEPLOY_LOCK_IDENTITY:-} ]] || {
  echo "vps_deploy_master: no inherited parent deployment lock" >&2
  exit 75
}
[[ -d $lock_dir && ! -L $lock_dir && -f $lock_dir/owner && ! -L $lock_dir/owner ]] || {
  echo "vps_deploy_master: parent deployment lock record is missing or unsafe" >&2
  exit 75
}
read -r owner_pid owner_host owner_epoch owner_identity < "$lock_dir/owner" || {
  echo "vps_deploy_master: cannot read parent deployment lock record" >&2
  exit 75
}
[[ $owner_pid == "$VPS_DEPLOY_LOCK_PID" && $owner_host == "$(hostname -s)" &&
   $owner_epoch == <-> && $owner_identity == "$VPS_DEPLOY_LOCK_IDENTITY" ]] || {
  echo "vps_deploy_master: parent lock record does not match the inherited identity" >&2
  exit 75
}
owner_started=$(LC_ALL=C ps -p "$owner_pid" -o lstart= 2>/dev/null) || { echo "vps_deploy_master: cannot read parent start time" >&2; exit 75; }
owner_command=$(ps -ww -p "$owner_pid" -o command= 2>/dev/null) || { echo "vps_deploy_master: cannot read parent command" >&2; exit 75; }
[[ -n $owner_started && -n $owner_command ]] || { echo "vps_deploy_master: parent identity unavailable" >&2; exit 75; }
owner_started=${owner_started//[^A-Za-z0-9]/_}
owner_digest=$(print -rn -- "$owner_command" | cksum) || { echo "vps_deploy_master: cannot fingerprint parent process" >&2; exit 75; }
owner_digest=${owner_digest// /_}
[[ ${owner_started}_${owner_digest} == "$owner_identity" ]] || {
  echo "vps_deploy_master: parent deployment process identity changed" >&2
  exit 75
}

# Workstation preflight and parent load admission must already pass.
cd "$ROOT"
[ -n "${VPS_DEPLOY_SHA:-}" ] || {
  echo "vps_deploy_master: refused - invoke MASTER/bin/operator vps deploy master --remote" >&2
  exit 69
}
head=$(/usr/bin/su -s /bin/sh "$deploy_user" -c "cd /home/dev/pub5 && git rev-parse HEAD")
[ "$head" = "$VPS_DEPLOY_SHA" ] || {
  echo "vps_deploy_master: HEAD $head does not match pinned SHA $VPS_DEPLOY_SHA" >&2
  exit 1
}
[ "${VPS_DEPLOY_ADMITTED_SHA:-}" = "$VPS_DEPLOY_SHA" ] || {
  echo "vps_deploy_master: no matching parent load-admission token; refusing direct execution" >&2
  exit 69
}
if [ -n "${VPS_DEPLOY_PREFLIGHT_SHA:-}" ]; then
  [ "$VPS_DEPLOY_PREFLIGHT_SHA" = "$VPS_DEPLOY_SHA" ] || {
    echo "vps_deploy_master: workstation preflight SHA does not match; refusing" >&2
    exit 69
  }
else
  [ "${VPS_DEPLOY_SKIP_PREFLIGHT:-}" = 1 ] && [ "${I_UNDERSTAND_FAST_DEPLOY:-}" = 1 ] || {
    echo "vps_deploy_master: no workstation preflight; refusing direct execution" >&2
    exit 69
  }
fi
echo "==> pinned checkout and parent admission verified: $VPS_DEPLOY_SHA"

cd "$WEB"
export LANG=C.UTF-8 LC_ALL=C.UTF-8
export RAILS_ENV=production
# The verification and migration steps need Rails to boot but never use the
# production key; the running service takes its key from /etc/master.env.
# SECRET_KEY_BASE_DUMMY makes that explicit.
export SECRET_KEY_BASE_DUMMY=1

# Primary database. MASTER/web's migrations reach ai.brgen.no's
# production.sqlite3 through this step and no other, so a deploy without it
# ships code against a schema that is behind.
#
# db:prepare is idempotent: it creates the database when absent, loads the
# schema when empty, and otherwise applies only pending migrations. The frozen
# bundle checks above refuse missing OpenBSD gems before touching the database.
echo "==> verify preinstalled production bundles"
BUNDLE_PATH_DEV=/home/dev/.bundle/master
export BUNDLE_WITHOUT=development:test BUNDLE_PATH="$BUNDLE_PATH_DEV" BUNDLE_FROZEN=true
for gemfile in "$WEB/Gemfile" "$ROOT/MASTER/Gemfile"; do
  (cd "${gemfile%/Gemfile}" && BUNDLE_GEMFILE="$gemfile" "$BUNDLE" check) || {
    echo "vps_deploy_master: production bundle incomplete for $gemfile; build it on a matching OpenBSD builder" >&2
    exit 1
  }
done
asset_dir="$WEB/public/assets"
asset_manifest="$asset_dir/.manifest.json"
asset_stamp="$asset_dir/.pub5-build-sha"
[ -d "$asset_dir" ] && [ ! -L "$asset_dir" ] || {
  echo "vps_deploy_master: prebuilt public/assets directory missing; refusing host-side compilation" >&2
  exit 1
}
[ -s "$asset_manifest" ] && [ ! -L "$asset_manifest" ] || {
  echo "vps_deploy_master: prebuilt production asset manifest missing; refusing host-side compilation" >&2
  exit 1
}
[ -s "$asset_stamp" ] && [ ! -L "$asset_stamp" ] || {
  echo "vps_deploy_master: workstation asset attestation missing; refusing host-side compilation" >&2
  exit 1
}
[ "$(cat "$asset_stamp")" = "${VPS_DEPLOY_SHA:-}" ] || {
  echo "vps_deploy_master: assets do not match the pinned source SHA" >&2
  exit 1
}

echo "==> verify prebuilt assets"
# The asset check, through whichever door exists. MASTER/checks/runner.rb was
# deleted on 2026-09-16 and every deploy script still named it, so `vps-deploy
# master` died here under set -e with the box half deployed: new assets on disk,
# the old process still serving them. The check itself lives in MASTER/checks and
# runs either way. It stays ahead of the database step: assets that fail
# attestation must stop the deploy before any migration runs.
if [ -f "$ROOT/MASTER/checks/runner.rb" ]; then
  BUNDLE_WITHOUT=development:test "$BUNDLE" exec ruby "$ROOT/MASTER/checks/runner.rb" master_web_assets
else
  BUNDLE_WITHOUT=development:test "$BUNDLE" exec ruby -e '
    require ARGV[0]
    Deploy::MasterWebAssetsCheck.run.report!("master web assets ok")
  ' "$ROOT/MASTER/lib/operator/checks.rb"
fi

echo "==> db prepare"
BUNDLE_GEMFILE="$WEB/Gemfile" BUNDLE_WITHOUT=development:test "$BUNDLE" exec rails db:prepare

echo "==> runtime dirs"
doas /bin/ksh -c '
  set -eu
  root=/home/dev/pub5/MASTER/web
  for path in /home /home/dev /home/dev/pub5 /home/dev/pub5/MASTER "$root"; do
    [ -d "$path" ] && [ ! -L "$path" ] || { echo "unsafe MASTER web path: $path" >&2; exit 1; }
  done
  for name in tmp log; do
    path=$root/$name
    [ ! -L "$path" ] || { echo "refusing symlinked runtime directory: $path" >&2; exit 1; }
    [ -d "$path" ] || install -d -o dev -g master -m 2775 "$path"
    links=$(find "$path" -type l -print | head -n 1)
    [ -z "$links" ] || { echo "symlink inside runtime directory: $links" >&2; exit 1; }
    chown -R dev:master "$path"
    chmod -R u+rwX,g+rwX "$path"
    find "$path" -type d -exec chmod 2775 {} +
  done
'
# MASTER/.master is shared the same way (rc.d/master documents it), but nothing
# enforced it: a boot left it 0700 and root left files in it, so the restarted
# daemon could not make its TTS sockets and the smoke failed on "tts_socket
# false" (2026-11-25). Group gets it, others never do. Only the directory
# itself is shared: Trace::Recorder keeps traces/ owner-private and refuses it
# otherwise, so a recursive group grant stopped the daemon booting. traces/
# belongs to its writer, the daemon. OpenBSD's chown -R and chmod -R follow no
# symlinks inside the tree (-P is their default).
state="$ROOT/MASTER/.master"
[[ ! -L $state ]] || { echo "refusing symlinked state directory: $state" >&2; exit 1; }
[[ -d $state ]] || doas install -d -o dev -g master -m 2770 "$state"
doas chown dev:master "$state"
doas chmod 2770 "$state"
if [[ -d $state/traces && ! -L $state/traces ]]; then
  doas chown -R master:master "$state/traces"
  doas chmod -R u+rwX,go-rwx "$state/traces"
fi
echo "==> sync rc.d master"
if [ -f "$ROOT/OPENBSD/mirror/etc/rc.d/master" ]; then
  if ! cmp -s "$ROOT/OPENBSD/mirror/etc/rc.d/master" /etc/rc.d/master; then
    echo "installed /etc/rc.d/master differs; run the reviewed OPERATOR.sh sync before deploying" >&2
    exit 1
  fi
fi

echo "==> restart master"
doas /usr/sbin/rcctl restart master
sleep 4
rcctl check master

echo "==> smoke"
curl -fsS http://127.0.0.1:53187/up
# /health runs the TTS worker's --selftest on its first call and keeps a failed
# answer for a minute, so one early miss under the restart's load is not a
# verdict. Poll for two minutes; the last attempt's reason (the "blocked" field
# /health prints on a 503) is what the operator reads.
_health_ok=0
_try=0
while [ "$_try" -lt 8 ]; do
  if curl -sS http://127.0.0.1:53187/health | ruby -rjson -e 'h=JSON.parse(STDIN.read); d=h["deploy"]||{}; abort("tts_socket false: #{h["blocked"].inspect}") if d["tts_socket"]==false; abort("checks.tts false: #{h["blocked"].inspect}") if h.dig("checks","tts")==false; puts "health ok sha=#{d["git_sha"]} tts_socket=#{d["tts_socket"]}"'; then
    _health_ok=1
    break
  fi
  _try=$((_try + 1))
  sleep 15
done
[ "$_health_ok" = 1 ] || exit 1
ruby "$WEB/script/probe_http"

echo "==> master deploy ok"
