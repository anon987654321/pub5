#!/bin/ksh
# Unprivileged recovery wrapper. Uses OpenBSD's native doas and rcctl.
set -eu

case ${1:-} in
  -h|--help)
    echo "usage: ksh OPENBSD/bin/start_all_apps.sh - start every registered production app and pin the fleet"
    exit 0
    ;;
  "") ;;
  *) echo "start_all_apps: no arbitrary arguments are accepted" >&2; exit 2 ;;
esac

if [ "$(id -u)" -eq 0 ]; then
  echo "start_all_apps: run this as dev; doas performs the privileged operations" >&2
  exit 2
fi

ROOT=/home/dev/pub5
[ -d "$ROOT/.git" ] && [ ! -L "$ROOT" ] || {
  echo "start_all_apps: repository checkout is missing or symlinked" >&2
  exit 1
}
. "$ROOT/OPENBSD/lib/ruby_select.sh"

# Service names are derived from the canonical inventory. The shell boundary
# accepts only simple service identifiers, never arbitrary command fragments.
services=$("$RUBY" -r"$ROOT/OPENBSD/lib/deploy_inventory" -e '
  names = Deploy::Inventory.new(root: ARGV.fetch(0)).app_names
  abort "invalid service identifier in RAILS/apps.yml" unless names.all? { |name| name.match?(/\A[a-z][a-z0-9_]{0,31}\z/) }
  puts names
' "$ROOT") || exit 1
[ -n "$services" ] || {
  echo "start_all_apps: RAILS/apps.yml contains no deployable apps" >&2
  exit 1
}

# Keep the resource guard from shedding optional services while the operator
# explicitly asks for the complete inventory to stay online.
doas /bin/ksh -c '
  set -eu
  flag=/var/db/pub5_all_apps
  [ -d /var/db ] && [ ! -L /var/db ] && [ "$(stat -f %u /var/db)" -eq 0 ] || {
    echo "start_all_apps: /var/db must be a real root-owned directory" >&2
    exit 1
  }
  [ ! -L "$flag" ] || {
    echo "start_all_apps: refusing symlinked fleet flag" >&2
    exit 1
  }
  if [ -e "$flag" ]; then
    [ -f "$flag" ] && [ "$(stat -f %u "$flag")" -eq 0 ] || {
      echo "start_all_apps: existing fleet flag is not a root-owned regular file" >&2
      exit 1
    }
  else
    umask 022
    : > "$flag"
  fi
  chown root:wheel "$flag"
  chmod 644 "$flag"
  for service do
    case "$service" in
      ""|*[!a-z0-9_]*)
        echo "start_all_apps: invalid service identifier: $service" >&2
        exit 64
        ;;
    esac
    /usr/sbin/rcctl enable "$service"
    /usr/sbin/rcctl start "$service"
  done
' start_all_apps $services

"$RUBY" "$ROOT/OPENBSD/checks/health_check.rb" --all-ready-apps
echo "all registered apps up (resource_guard shedding disabled via /var/db/pub5_all_apps)"
