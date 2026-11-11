#!/bin/ksh
# Root-owned launcher; project code is executed only after su drops to the app user.
set -eu
PATH=/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin
export PATH

app=${1:-}
timeout=${2:-}
case "$app" in
  brgen|amber|bsdports|mrdamascy) ;;
  *) echo "ci-run: refused unknown app: $app" >&2; exit 64 ;;
esac
case "$timeout" in
  ""|*[!0-9]*) echo "ci-run: timeout must be an integer from 1 to 7200" >&2; exit 64 ;;
esac
[ "$timeout" -ge 1 ] && [ "$timeout" -le 7200 ] || {
  echo "ci-run: timeout must be an integer from 1 to 7200" >&2
  exit 64
}
[ "$(id -u)" -eq 0 ] || { echo "ci-run: must run as root through pub4-admin" >&2; exit 77; }

bundle=/usr/local/bin/bundle
ruby_path=/usr/local/bin/ruby
if [ ! -x "$ruby_path" ]; then
  ruby_path=
  for candidate in /usr/local/bin/ruby[0-9]*; do
    [ -x "$candidate" ] || continue
    ruby_path=$candidate
    break
  done
fi
[ -n "$ruby_path" ] || { echo "ci-run: no system Ruby found" >&2; exit 127; }
base=${ruby_path##*/}
suffix=${base#ruby}
candidate="/usr/local/bin/bundle$suffix"
[ ! -x "$candidate" ] || bundle=$candidate
[ "$found_ruby" -eq 1 ] || { echo "ci-run: no supported system Ruby found" >&2; exit 127; }
[ -x "$bundle" ] || { echo "ci-run: no supported system Bundler found" >&2; exit 127; }

# app and timeout have already passed closed allowlists. Bundle is chosen only
# from fixed system paths; no caller-supplied command, path or shell fragment crosses.
script=$(cat <<EOF
set -eu
export HOME=/home/$app
export PUB5_ROOT=/home/dev/pub5
export PUB4_CI_GUARD=1
export PUB4_CI_APP=$app
export PUB4_CI_TIMEOUT=$timeout
export PUB5_RAILS_ROOT=/home/$app/pub4-rails/RAILS
export NPM_CONFIG_CACHE=/home/$app/.npm
export XDG_CACHE_HOME=/home/$app/.cache
export BUNDLE_USER_HOME=/home/$app/.bundle
unset RUBYOPT RUBYLIB RUBYPATH RUBYGEMS_GEMDEPS GEM_HOME GEM_PATH
unset BUNDLE_GEMFILE BUNDLE_PATH BUNDLE_BIN_PATH BUNDLE_WITH BUNDLE_WITHOUT
cd /home/$app/app
$bundle config unset without >/dev/null 2>&1 || :
$bundle config unset deployment >/dev/null 2>&1 || :
$bundle install --jobs=2
$bundle exec bin/ci
EOF
)
exec /usr/bin/su -m "$app" -c "$script"
