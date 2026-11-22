#!/usr/bin/env zsh
set -euo pipefail
# _bundle.sh — bundler and npm-cache helpers.
# Source this file; do not execute directly. Requires _core.sh sourced first.

bundle_exec() {
  "$BUNDLE" "$@"
}

add_gem() {
  local gem=$1 ver=${2:-}
  if ! grep -q "\"${gem}\"" Gemfile 2>/dev/null; then
    if [[ -n $ver ]]; then
      print "gem \"${gem}\", \"${ver}\"" >> Gemfile
    else
      print "gem \"${gem}\"" >> Gemfile
    fi
    log_ok "gem ${gem} added"
  else
    log_ok "gem ${gem} already present"
  fi
}

add_gem_group() {
  local groups=$1; shift
  local -a gems=("$@")
  if ! grep -q "gem \"${gems[1]}\"" Gemfile 2>/dev/null; then
    {
      print "group :${groups//,/, :} do"
      for g in "${gems[@]}"; do print "  gem \"$g\""; done
      print "end"
    } >> Gemfile
  fi
}

# ensure_npm_cache APP_NAME — sass-embedded native build must not write /root/.npm via doas.
ensure_npm_cache() {
  local app_name=$1
  run_rails_as_app "$app_name" "/home/${app_name}/app" "npm-cache"
}

# Each app owns its own Bundler cache. Avoid a root-owned cross-app CAS:
# the small VM saves less than the extra ownership, digest and migration logic costs.
# bundle_install_as_app APP_NAME APP_DIR — production bundle as the app user.
bundle_install_as_app() {
  local app_name=$1
  local app_dir=$2
  [[ $app_dir == "/home/${app_name}/app" ]] || {
    log_err "bundle_install_as_app: refused app path: $app_dir"
    return 2
  }
  run_rails_as_app "$app_name" "$app_dir" "bundle-install"
}
