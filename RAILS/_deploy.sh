#!/usr/bin/env zsh
# _deploy.sh — orchestrator for the copy-tree deploy pipeline. Sources every
# sibling _*.sh helper file, then exposes deploy_tracked_app as the single
# entry point each app's <app>.sh script calls.
#
# Requires: zsh, a Ruby and bundler (OPENBSD/lib/ruby_select.sh picks them), rails, doas
set -euo pipefail

typeset _deploy_sh_dir=${${(%):-%x}:A:h}

. "${_deploy_sh_dir:h}/OPENBSD/lib/ruby_select.sh"

. "${_deploy_sh_dir}/_core.sh"
. "${_deploy_sh_dir}/_bundle.sh"
. "${_deploy_sh_dir}/_sync.sh"
. "${_deploy_sh_dir}/_database.sh"
. "${_deploy_sh_dir}/_assets.sh"
. "${_deploy_sh_dir}/_runtime_check.sh"
. "${_deploy_sh_dir}/_service.sh"

# deploy_tracked_app APP_NAME — sync the app tree, verify bundle/assets, migrate and restart.
deploy_tracked_app() {
  local app_name=${1:-$APP_NAME}
  case "$app_name" in
    brgen|amber|bsdports|mrdamascy) ;;
    *) log_err "deploy_tracked_app: refused unknown app: $app_name"; return 2 ;;
  esac

  need_cmd "$RUBY" "$BUNDLE" doas curl

  [[ -d $SRC_DIR ]] || { log_err "missing source tree: $SRC_DIR"; exit 1; }
  [[ -d /home && ! -L /home ]] || { log_err "unsafe /home directory"; return 1; }

  log "${app_name} - deploying tracked tree -> ${APP_DIR}"
  deploy_status "$app_name" "sync tree"

  # Create only this inventory-approved app account and its own home. Existing
  # homes are never recursively chowned or repaired through symlinks.
  if ! id "$app_name" >/dev/null 2>&1; then
    ${_PRIV} /usr/sbin/useradd -m -L daemon -s /bin/ksh "$app_name" || {
      log_err "could not create app account $app_name"
      return 1
    }
  fi
  local app_home="/home/$app_name"
  if [[ -L $app_home || ! -d $app_home ]]; then
    log_err "app home is missing, symlinked or not a directory: $app_home"
    return 1
  fi
  local app_home_owner
  app_home_owner=$(/usr/bin/stat -f %Su "$app_home") || return 1
  [[ $app_home_owner == "$app_name" ]] || {
    log_err "app home $app_home is owned by $app_home_owner, not $app_name"
    return 1
  }
  if [[ ! -e $APP_DIR && ! -L $APP_DIR ]]; then
    ${_PRIV} /usr/bin/install -d -o "$app_name" -g "$app_name" -m 755 "$APP_DIR" || return 1
  fi
  [[ -d $APP_DIR && ! -L $APP_DIR ]] || {
    log_err "app directory is unsafe: $APP_DIR"
    return 1
  }
  [[ $(/usr/bin/stat -f %Su "$APP_DIR") == "$app_name" ]] || {
    log_err "app directory is not owned by $app_name: $APP_DIR"
    return 1
  }

  # The installed helper grants the selected app only the checkout-read group
  # and verifies every path before changing ownership or permissions.
  [[ -x /usr/local/libexec/ci-prepare.ksh && ! -L /usr/local/libexec/ci-prepare.ksh ]] || {
    log_err "installed ci-prepare.ksh is missing or untrusted; run OPERATOR.sh"
    return 1
  }
  ${_PRIV} /usr/local/libexec/ci-prepare.ksh "$app_name" || {
    log_err "app checkout access preparation failed for $app_name"
    return 1
  }

  rails_sync_app_tree "$app_name" app
  # mrdamascy is standalone: its Gemfile names no shared-engine path gem, and the
  # shared initializers would load Shared:: constants it never defines.
  if [[ $app_name != mrdamascy ]]; then
    rails_sync_app_tree "$app_name" shared
    if [[ $app_name == brgen ]]; then
      # Compatibility no-op under the pub5 layout: the vertical engines ride
      # inside the app tree (brgen/engines/), so there are no brgen_* siblings
      # to sync. Kept so older operator runbooks stay truthful.
      rails_sync_app_tree "$app_name" verticals
    fi
    overlay_shared_initializers "$APP_DIR"
    overlay_shared_public "$APP_DIR"
  fi
  # The app-user sync preserves log, storage and compiled public/assets in the
  # staged replacement. No root chown of checkout-owned tree content is needed.

  local repo_root checkout_sha asset_dir asset_manifest asset_stamp
  repo_root="${_deploy_sh_dir:h}"
  checkout_sha=$(git -C "$repo_root" rev-parse HEAD) || {
    log_err "cannot read pinned checkout SHA"
    return 1
  }
  [[ ${VPS_DEPLOY_SHA:-} == "$checkout_sha" && ${VPS_DEPLOY_CI_SHA:-} == "$checkout_sha" ]] || {
    log_err "refusing per-app deploy without workstation CI attestation for exact checkout SHA"
    return 1
  }
  run_rails_as_app "$app_name" "$APP_DIR" "bundle-check" || {
    log_err "preinstalled production bundle is incomplete; build it on a matching OpenBSD builder"
    return 1
  }
  asset_dir="$APP_DIR/public/assets"
  asset_manifest="$asset_dir/.manifest.json"
  asset_stamp="$asset_dir/.pub5-build-sha"
  [[ -d $asset_dir && ! -L $asset_dir && -s $asset_manifest && ! -L $asset_manifest &&
     -s $asset_stamp && ! -L $asset_stamp && "$(<"$asset_stamp")" == "$checkout_sha" ]] || {
    log_err "workstation-built assets are missing or do not match the pinned SHA"
    return 1
  }

  cd "$APP_DIR"
  # Both the one-time db/ → storage/ relocation and db:prepare mutate the live
  # SQLite files. A Falcon worker can keep the source inode open and hold WAL
  # locks, so prove the service is stopped before either operation begins.
  if pub4_rcctl check "$app_name" >/dev/null 2>&1; then
    pub4_rcctl stop "$app_name" || {
      log_err "could not stop ${app_name}; refusing to move or migrate its SQLite database"
      return 1
    }
    if pub4_rcctl check "$app_name" >/dev/null 2>&1; then
      log_err "${app_name} still reports running after stop; refusing database changes"
      return 1
    fi
  fi
  migrate_sqlite_db_to_storage_if_needed "$APP_NAME" "$APP_DIR"
  deploy_status "$app_name" "db migrate"
  db_create_migrate_as_app "$APP_NAME" "$APP_DIR" || { deploy_status "$app_name" "db migrate" "failed"; exit 1; }
  log_ok "database migrated for ${app_name}"
  if [[ ${RUN_PRODUCTION_SEEDS:-} == 1 && ${SEED_ON_DEPLOY:-} != 1 ]]; then
    SEED_ON_DEPLOY=1
  fi
  if [[ -f ${APP_DIR}/db/seeds.rb && ${SEED_ON_DEPLOY:-} == 1 ]]; then
    db_seed_as_app "$APP_NAME" "$APP_DIR"
  fi

  install_rcd "$APP_NAME" "$APP_DIR" "$APP_PORT" "$APP_NAME"
  [[ -n $APP_DOMAIN ]] && relayd_add_relay "$APP_NAME" "$APP_DOMAIN" "$APP_PORT"

  rails_runtime_check "$APP_NAME" "$APP_DIR" || { deploy_status "$app_name" "runtime check" "failed"; exit 1; }
  if [[ ${DEMO_SEED_ON_DEPLOY:-0} == 1 ]]; then
    deploy_status "$app_name" "demo seed"
    if [[ $app_name == brgen || $app_name == amber ]]; then
      seed_demo_as_app "$APP_NAME" "$APP_DIR"
    fi
  fi
  deploy_status "$app_name" "restart"
  pub4_rcctl restart "$APP_NAME" || pub4_rcctl start "$APP_NAME"
  post_restart_probe "$APP_NAME" "$APP_PORT" \
    || { deploy_status "$app_name" "restart" "failed"; exit 1; }
  if [[ $app_name == brgen ]]; then
    warm_brgen_after_restart "$APP_PORT"
  fi
  deploy_status "$app_name" "done" "done"
  log_ok "$APP_NAME live on :$APP_PORT"
}
