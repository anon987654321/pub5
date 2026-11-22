#!/usr/bin/env zsh
set -euo pipefail
# _sync.sh — copy-tree sync and fixed app-user shared-file overlays.
# Source this file; do not execute directly. Requires _core.sh sourced first.

# Production tree replacement runs as the owning app user. No root copy, delete
# or rename is needed: doas reaches su, then the fixed installed helper performs
# the staged sync inside that app's home.
# rails_sync_app_tree APP_NAME MODE — fixed app-user tree synchronization.
# Source and destination paths are owned by the installed broker helper, not caller input.
rails_sync_app_tree() {
  local app_name=$1 mode=$2
  case "$app_name" in
    brgen|amber|bsdports|mrdamascy) ;;
    *) log_err "rails_sync_app_tree: refused app: $app_name"; return 2 ;;
  esac
  case "$mode" in
    app|shared) ;;
    verticals)
      [[ $app_name == brgen ]] || { log_err "rails_sync_app_tree: verticals are brgen-only"; return 2; }
      ;;
    *) log_err "rails_sync_app_tree: refused mode: $mode"; return 2 ;;
  esac
  [[ -x /usr/local/libexec/rails-sync.ksh && ! -L /usr/local/libexec/rails-sync.ksh ]] || {
    log_err "rails_sync_app_tree: installed rails-sync.ksh is missing or untrusted; run OPERATOR.sh"
    return 1
  }
  "${_PRIV}" /usr/bin/su -m "$app_name" -c "/usr/local/libexec/rails-sync.ksh $app_name $mode"
}
# overlay_shared_initializers APP_DIR — shared config wins over stale per-app copies
overlay_shared_initializers() {
  local app_dir=$1
  local shared_init=${PUB5_RAILS_ROOT:-/home/dev/pub5/RAILS}/__shared/config/initializers
  [[ -d $shared_init ]] || return 0
  local app_name=${app_dir:h:t}
  run_rails_as_app "$app_name" "$app_dir" "overlay-initializers" || return $?
  log_ok "shared initializers overlaid (merge, app-specific files preserved)"
}

# overlay_shared_public APP_DIR — merge shared/public (tokens, error pages, fonts).
# Never clobber per-app brand icons/manifests (amber palette, etc.).
overlay_shared_public() {
  local app_dir=$1
  local shared_public=${PUB5_RAILS_ROOT:-/home/dev/pub5/RAILS}/__shared/public
  [[ -d $shared_public ]] || return 0
  local app_name=${app_dir:h:t}
  run_rails_as_app "$app_name" "$app_dir" "overlay-public" || return $?
  log_ok "shared public assets and bin stubs overlaid"
}
