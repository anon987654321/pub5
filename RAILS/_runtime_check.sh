#!/usr/bin/env zsh
set -euo pipefail
# _runtime_check.sh — MASTER rules scan and the full CI check (bundle + db:prepare
# + bin/ci) that must pass before a deploy is allowed to restart the service.
# Source this file; do not execute directly. Requires _core.sh sourced first.

# master_scan_dep APP_NAME — laws.yml check via MASTER CLI (requires bundle exec in MASTER/).
master_scan_dep() {
  local app_name=$1
  local master=${MASTER_ROOT:-/home/dev/pub5/MASTER}
  local log_dir=/var/db/pub5
  local log=${log_dir}/master_${app_name}_scan.log
  # The scan runs in the deploy role, while /var/db/pub5 belongs to root
  # (the deployer writes the durable records there). A deploy run under
  # run_as_deploy_user found
  # the directory unwritable on vm23 2026-11-08: keep the durable location
  # when the runner owns it, else fall back to the runner's tmpdir so the
  # scan still runs and its evidence still lands in the deploy run log.
  if [[ ! -w $log_dir ]]; then
    local refused=$log_dir
    log_dir=${TMPDIR:-/tmp}
    log=${log_dir}/master_${app_name}_scan.log
    log_warn "MASTER scan log at ${log} (${refused} not writable for $(id -un))"
  fi
  if [[ ${SKIP_MASTER_SCAN:-0} != 0 ]]; then
    if [[ ${SKIP_MASTER_SCAN} != 1 || ${I_UNDERSTAND_FAST_DEPLOY:-0} != 1 ]]; then
      log_err "SKIP_MASTER_SCAN=1 requires I_UNDERSTAND_FAST_DEPLOY=1"
      return 1
    fi
    log_warn "MASTER scan skipped by explicit fast-deploy acknowledgement"
    return 0
  fi
  [[ -x ${master}/bin/master ]] || { log_err "MASTER scan unavailable at ${master}"; return 1; }
  mkdir -p "$log_dir" || { log_err "cannot create ${log_dir} for MASTER scan log"; return 1; }
  [[ -O $log_dir ]] && chmod 700 "$log_dir"
  log "MASTER rules scan (OPERATOR) pre-bundle"
  if ! (cd "$master" && MASTER_SCAN_DETERMINISTIC=1 MASTER_SAFE_MODE=1 bundle_exec exec ruby bin/check --scan-only --tree=RAILS) \
    </dev/null >"$log" 2>&1; then
    cat "$log" >&2
    log_err "MASTER scan CLI failed"
    return 1
  fi
  cat "$log" >&2
  if grep -Eq '[1-9][0-9]* total violations|scan[0-9]*: .*([1-9][0-9]*) violations' "$log"; then
    log_err "MASTER scan found violations (evidence_scoring scan_clean check)"
    return 1
  fi
  log_ok "MASTER scan clean"
}

# run_rails_as_app APP_NAME APP_DIR CMD — app-owned bundle/rails (avoids Gemfile.lock permission errors).
run_rails_as_app() {
  local app_name=$1 app_dir=$2 task=${3:-} database=${4:-}
  case "$app_name" in
    master|brgen|amber|bsdports|mrdamascy) ;;
    *) log_err "run_rails_as_app: refused app: $app_name"; return 2 ;;
  esac
  [[ $app_dir == "/home/${app_name}/app" ]] || { log_err "run_rails_as_app: refused app path: $app_dir"; return 2; }
  case "$task" in
    bundle-check|bundle-sibling-hydrate|bundle-install|db-storage-migrate|db-prepare|db-seed|demo-seed|\
overlay-initializers|overlay-public) [[ -z $database ]] || return 2 ;;
    schema-load|secondary-db-check) [[ $database == cache || $database == queue || $database == cable ]] || return 2 ;;
    bundle-cas-hydrate)
      [[ $database == ruby[0-9][0-9] || $database == ruby[0-9].[0-9] ]] || return 2 ;;
    *) log_err "run_rails_as_app: refused task: $task"; return 2 ;;
  esac
  [[ $task != demo-seed || $app_name == brgen || $app_name == amber ]] || return 2

  [[ -x /usr/local/libexec/rails-task.ksh && ! -L /usr/local/libexec/rails-task.ksh ]] || {
    log_err "run_rails_as_app: installed rails-task.ksh is missing or untrusted; run OPERATOR.sh"
    return 1
  }
  if [[ $task == schema-load || $task == secondary-db-check || $task == bundle-cas-hydrate ]]; then
    ${_PRIV} /usr/local/libexec/rails-task.ksh "$app_name" "$task" "$database"
  else
    ${_PRIV} /usr/local/libexec/rails-task.ksh "$app_name" "$task"
  fi
}

# rails_runtime_check APP_NAME APP_DIR — read-only bundle, asset and essential DB checks.
rails_runtime_check() {
  local app_name=${1:-}
  local app_dir=${2:-$1}
  local checkout_sha asset_dir asset_manifest asset_stamp
  [[ -d $app_dir && ! -L $app_dir ]] || {
    log_err "rails_runtime_check: missing or unsafe ${app_dir}"
    return 1
  }
  checkout_sha=$(git -C /home/dev/pub5 rev-parse HEAD) || {
    log_err "cannot read pinned checkout SHA"
    return 1
  }
  [[ ${VPS_DEPLOY_SHA:-} == "$checkout_sha" && ${VPS_DEPLOY_CI_SHA:-} == "$checkout_sha" ]] || {
    log_err "runtime check requires workstation CI attestation for the exact pinned SHA"
    return 1
  }
  asset_dir="$app_dir/public/assets"
  asset_manifest="$asset_dir/.manifest.json"
  asset_stamp="$asset_dir/.pub5-build-sha"
  [[ -d $asset_dir && ! -L $asset_dir && -s $asset_manifest && ! -L $asset_manifest &&
     -s $asset_stamp && ! -L $asset_stamp ]] || {
    log_err "workstation-built production assets or SHA marker are missing"
    return 1
  }
  [[ $(<"$asset_stamp") == "$checkout_sha" ]] || {
    log_err "production asset SHA does not match the pinned checkout"
    return 1
  }
  if [[ -n $app_name ]]; then
    deploy_status "$app_name" "runtime check: bundle check"
    run_rails_as_app "$app_name" "$app_dir" "bundle-check" \
      || { deploy_status "$app_name" "runtime check: bundle check" "failed"; log_err "production bundle check failed"; return 1; }
    deploy_status "$app_name" "runtime check: db:prepare"
    run_rails_as_app "$app_name" "$app_dir" "db-prepare" \
      || { deploy_status "$app_name" "runtime check: db:prepare" "failed"; log_err "db:prepare failed"; return 1; }
    deploy_status "$app_name" "runtime check: secondary dbs"
    rails_prepare_secondary_dbs_as_app "$app_name" "$app_dir" \
      || { deploy_status "$app_name" "runtime check: secondary dbs" "failed"; return 1; }
  else
    (cd "$app_dir" && BUNDLE_FROZEN=true bundle_exec check) || { log_err "bundle check failed"; return 1; }
    (cd "$app_dir" && BUNDLE_FROZEN=true RAILS_ENV=production bundle_exec exec rails db:prepare) \
      || { log_err "db:prepare failed"; return 1; }
  fi
  log_ok "runtime bundle, assets and database checks passed"
}
