# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "socket"
require "yaml"
require_relative "../lib/deploy_inventory"
require "open3"

# vps-deploy is the entrypoint for every production deploy and had no test.
#
# Running it is not an option — it deploys — so this reads the source for the
# three things it promises that a reader cannot otherwise check: that the fleet
# it deploys is the fleet apps.yml declares, that the order which makes the pass
# survive its own side effects is still that order, and that it refuses to run as
# root rather than dying at `git pull` with a message about host keys.
class VpsDeployContractTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  SOURCE = File.read(File.join(ROOT, "OPENBSD", "bin", "vps-deploy"), encoding: "UTF-8")
  CI_SOURCE = File.read(File.join(ROOT, "OPENBSD", "bin", "vps_ci.sh"), encoding: "UTF-8")
  GUARD = File.read(File.join(ROOT, "OPENBSD", "mirror", "usr", "local", "bin", "resource_guard.sh"), encoding: "UTF-8")
  APPS = Deploy::Inventory.new(root: ROOT).app_names
  MASTER_DEPLOY = File.read(File.join(ROOT, "OPENBSD", "bin", "vps_deploy_master.sh"), encoding: "UTF-8")

  def test_deploy_entrypoint_has_one_complete_service_and_receipt_layer
    assert_equal 1, SOURCE.scan(/^admin_service\(\) \{$/).length
    assert_equal 1, SOURCE.scan(/^admin_request\(\) \{$/).length
    assert_equal 1, SOURCE.scan(/^write_deploy_run_receipt\(\) \{$/).length
    assert_equal "exit 0", SOURCE.lines.last.strip
  end

  def test_all_applies_the_filesystem_mirror_before_application_deploys
    assert_source SOURCE, 'zsh "$repo/OPENBSD/OPERATOR.sh" --apply'
    assert_operator SOURCE.index('OPENBSD/OPERATOR.sh" --apply'), :<, SOURCE.index('for one in $deploy_order')
  end

  def test_mirror_validation_and_verified_backups_precede_the_first_live_install
    operator = File.read(File.join(ROOT, "OPENBSD", "OPERATOR.sh"), encoding: "UTF-8")
    validate = operator.index("validate_payload ||")
    backup = operator.index('backup_file "$rel"')
    install = operator.index('install_one "$rel"')

    refute_nil validate
    refute_nil backup
    refute_nil install
    assert_operator validate, :<, backup
    assert_operator backup, :<, install
    assert_includes operator, 'file_matches "$rel" ||'
    assert_includes operator, "restore_files"
  end

  def test_mirror_apply_keeps_ssh_and_doas_changes_on_their_guarded_paths
    operator = File.read(File.join(ROOT, "OPENBSD", "OPERATOR.sh"), encoding: "UTF-8")
    assert_includes operator, 'PROTECTED /$rel (SSH configuration requires an out-of-band recovery path)'
    assert_includes operator, 'PROTECTED /$rel (pass --doas to use validate_doas.ksh)'
    assert_includes operator, 'validate_doas.ksh" install'
    # --doas installs doas.conf alone and defers the rest; refusing on other
    # changes left a drifted doas.conf with no path (vm23, 2026-11-25).
    assert_includes operator, "DEFERRED  ${#CHANGED} other mirror changes"
    refute_includes operator, "may only change doas.conf by itself"
  end

  def test_nsd_zone_changes_are_signed_and_validated_before_activation
    operator = File.read(File.join(ROOT, "OPENBSD", "OPERATOR.sh"), encoding: "UTF-8")
    apply = operator[operator.index('  apply)')..]
    backup = apply.index("backup_signed_zones ||")
    install = apply.index('install_one "$rel"')
    sign = apply.index("nsd-resign --force --no-reload")
    validate = apply.index('nsd-checkzone "${source_zone:t:r}" "$signed_zone"')
    activate = apply.index("rcctl restart nsd")

    refute_nil backup
    refute_nil install
    refute_nil sign
    refute_nil validate
    refute_nil activate
    assert_operator backup, :<, install
    assert_operator install, :<, sign
    assert_operator sign, :<, validate
    assert_operator validate, :<, activate
    assert_includes operator, "NSD_CONFIG_CHANGED"
  end

  def test_mirror_apply_does_not_turn_every_release_into_a_host_reboot
    operator = File.read(File.join(ROOT, "OPENBSD", "OPERATOR.sh"), encoding: "UTF-8")
    refute_match(/\b(?:reboot|shutdown)\b/, operator)
    assert_includes operator, 'rcctl restart relayd'
    assert_includes operator, 'rcctl restart httpd'
  end

  def test_success_stamp_follows_a_blocking_local_canary_for_every_app
    canary = SOURCE.index('if ! "$RUBY" "$repo/OPENBSD/bin/canary" --local --app "$app"')
    refute_nil canary
    ok_stamp = SOURCE.index('write_stamp "$app" ok', canary)
    failed_stamp = SOURCE.index('write_stamp "$app" failed', canary)

    refute_nil failed_stamp
    refute_nil ok_stamp
    assert_operator canary, :<, ok_stamp
    refute_includes SOURCE[canary...ok_stamp], "|| true"
  end

  def test_master_has_a_blocking_local_canary_before_its_success_stamp
    canary = SOURCE.index('master-canary')
    ok_stamp = SOURCE.index('write_stamp "$app" ok', canary)

    refute_nil canary
    refute_nil ok_stamp
    assert_operator canary, :<, ok_stamp
    assert_includes SOURCE[canary...ok_stamp], 'canary" --local --app "$app" --no-flows'
  end

  def test_deploy_scope_and_order_are_derived_from_inventory
    inventory = Deploy::Inventory.new(root: ROOT)
    all = inventory.ordered_apps
    rails = inventory.ordered_apps(group: "rails")
    degraded = inventory.ordered_apps(degraded: true)

    assert_equal inventory.apps.map(&:name).sort, all.map(&:name).sort
    assert_equal inventory.apps_for_group("rails").map(&:name).sort, rails.map(&:name).sort
    assert_equal all.map(&:name).sort, degraded.map(&:name).sort
    assert_equal "master", all.first.deploy_group
    assert_equal "master", degraded.last.deploy_group
    assert_source SOURCE, "Deploy::Inventory.new"
    assert_source SOURCE, "ordered_apps"
    assert_source SOURCE, "target_kind"
    refute_match(/DEPLOY_ALL=\([^)]*(?:brgen|amber|bsdports|mrdamascy)/, SOURCE)
  end

  def test_deploy_root_controls_group_membership_without_app_name_rules
    inventory = Deploy::Inventory.new(root: ROOT)
    inventory.apps.each do |app|
      assert_equal app.deploy_root.split("/", 2).first.downcase, app.deploy_group
    end
    assert_equal :unknown, inventory.target_kind("../outside")
    assert_source SOURCE, "unknown app or group"
  end

  def test_deploy_paths_export_openbsd_package_path
    expected = "export PATH=/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin"
    assert_source SOURCE, expected
    assert_source MASTER_DEPLOY, expected
  end

  def test_it_rejects_an_unknown_deploy_target
    inventory = Deploy::Inventory.new(root: ROOT)

    assert_equal :unknown, inventory.target_kind("../outside")
    assert_source SOURCE, "deploy_target_kind"
    assert_source SOURCE, "unknown app or group"
  end

  # The 2026-09-16 runner.rb deletion killed this deploy under set -e. The
  # conditional asset check is the fix; an unconditional call ahead of it, or a
  # second db:prepare, re-opens that outage and costs a second Rails boot on a
  # one-core box (found 2026-11-23).
  def test_master_deploy_prepares_the_database_once_and_checks_assets_only_through_the_guard
    assert_equal 1, MASTER_DEPLOY.scan('echo "==> db prepare"').length
    assert_equal 1, MASTER_DEPLOY.scan("rails db:prepare").length
    runner_calls = MASTER_DEPLOY.lines.grep(/exec ruby .*checks\/runner\.rb/)
    assert_equal 1, runner_calls.length
    guard = MASTER_DEPLOY.index('if [ -f "$ROOT/MASTER/checks/runner.rb" ]; then')
    assert guard, "the runner.rb existence guard is missing"
    assert_operator MASTER_DEPLOY.index(runner_calls.first), :>, guard
  end

  def test_master_deploy_refuses_root_override
    source = File.read(File.join(ROOT, "OPENBSD", "bin", "vps_deploy_master.sh"), encoding: "UTF-8")
    assert_includes source, 'if [ "$ROOT" != "/home/dev/pub5" ]; then'
    assert_includes source, "doas /usr/sbin/rcctl restart master"
    assert_includes source, "doas /bin/ksh -c"
    assert_includes source, 'find "$path" -type l'
    refute_includes source, "pub5-admin"
    refute_includes source, 'doas rm -rf public/assets'
    refute_includes source, 'doas chown -R dev:dev public'
    refute_includes source, 'doas cp "$ROOT/OPENBSD/mirror/etc/rc.d/master" /etc/rc.d/master'
  end
  def test_legacy_deploy_all_calls_the_canonical_operator_directly
    script = File.read(File.join(ROOT, "OPENBSD", "bin", "deploy_all.sh"), encoding: "UTF-8")
    assert_includes script, 'exec "${REPO_ROOT}/MASTER/bin/operator" vps deploy all --remote'
    refute_includes script, 'OPENBSD/bin/vps-deploy'
    refute_includes script, 'doas zsh'
    refute_includes script, 'RAILS/${app}/${app}.sh'
    refute File.exist?(File.join(ROOT, "MASTER", "bin", "redeploy"))
    refute File.exist?(File.join(ROOT, "OPENBSD", "bin", "redeploy"))
  end
  def test_ci_rejects_unknown_target_before_interpolating_a_path
    guard = CI_SOURCE[/^case \$app in\n.*?^esac$/m]
    refute_nil guard, "vps_ci app allowlist missing - arbitrary strings may reach path construction"
    assert_operator CI_SOURCE.index("case $app in"), :<, CI_SOURCE.index("app_dir=/home/${app}/app")

    out = IO.popen(
      ["zsh", "-c", "app='../outside'; #{guard}; print accepted", { err: %i[child out] }],
      &:read
    )

    assert_equal 2, $?.exitstatus
    assert_includes out, "unknown app"
    refute_includes out, "accepted"
  end

  def test_root_crontab_staging_is_private_from_deploy_receipts
    operator = File.read(File.join(ROOT, "OPENBSD", "OPERATOR.sh"))

    assert_includes operator, 'work=$(mktemp -d /var/db/pub5-crontab.XXXXXXXX)'
    assert_includes operator, 'chown root:wheel "$work"'
    assert_includes operator, 'chmod 700 "$work"'
    assert_includes operator, 'backup_root_crontab || {'
    assert_includes operator, 'verify_root_crontab || {'
  end
  def test_deploy_transcripts_never_create_files_on_vm23
    assert_source SOURCE, "deploy_log=/dev/null"
    assert_source SOURCE, "deploy_run_log=/dev/null"
    assert_source SOURCE, "VPS_DEPLOY_LOG_REF"
    assert_source SOURCE, "workstation_log=$deploy_log_ref"
    assert_source SOURCE, "workstation log reference is required"
    refute_source SOURCE, "exec > >(tee -a"
    refute_source SOURCE, 'mkdir -p -- "$deploy_log_dir/runs"'
    refute_source SOURCE, "/var/log/pub5/vps-deploy.log"
    refute_source SOURCE, "/home/dev/vps-deploy.log"
  end
  def test_remote_deploy_collector_polls_at_a_bounded_interval
    operator = File.read(File.join(ROOT, "MASTER", "bin", "operator"), encoding: "UTF-8")
    collector = operator[/def collect_remote_deploy\(.*?^end/m]
    capture = operator[/def remote_deploy_capture_command\(.*?^end/m]
    refute_nil collector
    refute_nil capture
    assert_includes collector, "sleep 3"
    assert_includes collector, "remote_deploy_capture_command(session)"
    assert_includes capture, "tmux capture-pane -p -J -S -"
  end

  def test_disk_usage_uses_native_bounded_du
    assert_source SOURCE, "disk-usage)"
    assert_source SOURCE, '/usr/bin/du -xk "$1"'
    refute_source SOURCE, "pub5-admin"
  end
  # vps-deploy runs as root, so its hints name native rcctl without doas.
  def test_failure_hints_use_native_rcctl
    assert_source SOURCE, "doas /usr/sbin/rcctl restart <app>"
    assert_source SOURCE, "doas /usr/sbin/rcctl start $app"
    assert_source SOURCE, "doas /usr/sbin/rcctl restart $other"
    refute_source SOURCE, "pub5-admin"
  end

  def test_vps_deploy_fails_closed_without_root_fallbacks
    assert_source SOURCE, 'records_call write "$VPS_DEPLOY_RUN_ID" "$payload"'
    assert_source SOURCE, "Deploy::Records.new(repo_root: repo)"
    refute_source SOURCE, "PUB5_ADMIN"
    refute_source SOURCE, "pub5-admin"
    refute_match(/^\s*doas\s+rcctl\b/, SOURCE)
    refute_match(/^\s*doas\s+(?:tee|chmod|mkdir)\b/, SOURCE)
    refute_source SOURCE, 'doas ksh "$repo/OPENBSD/bin/resource_guard.sh"'
    refute_source SOURCE, 'doas "$RUBY" "$repo/OPENBSD/checks/solid_queue_proof.rb"'
    refute_source SOURCE, 'doas tee "$file"'
  end
  def test_deploy_uses_native_rcctl_and_direct_records
    assert_source SOURCE, '"/usr/sbin/rcctl" "$action" "$service"'
    assert_source SOURCE, 'admin_request stamp "$name" "$sha" "$stamp_status"'
    assert_source SOURCE, "admin_request resource-guard"
    assert_source SOURCE, 'admin_request solid-queue-proof "$app"'
    assert_source SOURCE, 'records_call write "$@"'
  end

  # Since 6735acf1 the mirror is a copy-ready filesystem image: OPERATOR.sh
  # installs whatever git tracks under OPENBSD/mirror, and file_mode/file_owner
  # give privileged destinations the root:wheel treatment. The Solid Queue proof
  # is installed by BOOTSTRAP.sh, never from the live checkout.
  def test_operator_installs_app_user_helpers_and_solid_queue_proof
    operator = File.read(File.join(ROOT, "OPENBSD", "OPERATOR.sh"))
    bootstrap = File.read(File.join(ROOT, "OPENBSD", "BOOTSTRAP.sh"))

    refute File.exist?(File.join(ROOT, "OPENBSD", "mirror", "usr", "local", "sbin", "pub5-admin")),
           "the retired command broker must not be tracked in the mirror"
    assert_includes operator, "usr/local/sbin/*) print 555 ;;"
    assert_includes operator, "usr/local/libexec/*) print 755 ;;"
    assert_includes operator, "*) print root:wheel ;;"
    assert_includes operator, 'install -o "$owner" -g "$group" -m "$mode" "$source_file" "$tmp"'

    assert_includes bootstrap,
                    'install -o root -g wheel -m 555 "${SCRIPT_DIR}/checks/solid_queue_proof.rb" /usr/local/libexec/pub5/solid_queue_proof.rb'
    assert_includes bootstrap,
                    'install -o root -g wheel -m 555 "${SCRIPT_DIR}/checks/solid_queue_proof.rb" /usr/local/libexec/pub4/solid_queue_proof.rb'
  end

  def test_tree_sync_uses_the_fixed_app_user_helper
    sync = File.read(File.join(ROOT, "RAILS", "_sync.sh"), encoding: "UTF-8")
    refute_includes sync, "def sync_tree("
    refute_match(/\$\{_PRIV\}\s+(?:rm|mkdir|mv|tar|openrsync)\b/, sync)
    assert_includes sync, "/usr/local/libexec/rails-sync.ksh"
    assert_includes sync, '/usr/bin/su -m "$app_name"'
    assert_includes sync, 'case "$mode" in'
    assert_includes sync, "app|shared"
    assert_includes sync, "verticals"
    refute_includes sync, "pub5-admin"
  end
  def test_rails_task_runner_uses_the_fixed_helper
    runtime = File.read(File.join(ROOT, "RAILS", "_runtime_check.sh"), encoding: "UTF-8")
    runner = runtime[/run_rails_as_app\(\) \{.*?^\}/m]
    refute_nil runner
    assert_includes runner, "/usr/local/libexec/rails-task.ksh"
    assert_includes runner, "installed rails-task.ksh is missing or untrusted"
    refute_includes runner, "pub5-admin"
    refute_match(/\$\{_PRIV\} sh -c/, runner)
    refute_includes runtime, 'secret=$(app_secret_for "$app_name")'
  end
  def test_npm_cache_setup_uses_the_app_owned_task
    bundle = File.read(File.join(ROOT, "RAILS", "_bundle.sh"), encoding: "UTF-8")
    helper = bundle[/ensure_npm_cache\(\) \{.*?^\}/m]
    refute_nil helper
    assert_includes helper, 'run_rails_as_app "$app_name" "/home/${app_name}/app" "npm-cache"'
    refute_match(/\$\{_PRIV\}.*(?:mkdir|chown)/, helper)
  end
  def test_skip_ci_deploy_prepares_checkout_group_before_sync
    deploy = File.read(File.join(ROOT, "RAILS", "_deploy.sh"), encoding: "UTF-8")
    ensure_index = deploy.index('/usr/local/libexec/ci-prepare.ksh "$app_name"')
    access_index = deploy.index('rails_sync_app_tree "$app_name" app')

    refute_nil ensure_index
    refute_nil access_index
    assert_operator ensure_index, :<, access_index
  end
  def test_production_tree_sync_uses_the_fixed_app_user_helper
    deploy = File.read(File.join(ROOT, "RAILS", "_deploy.sh"), encoding: "UTF-8")
    sync = File.read(File.join(ROOT, "RAILS", "_sync.sh"), encoding: "UTF-8")
    block = deploy[/rails_sync_app_tree "\$app_name" app.*?overlay_shared_public "\$APP_DIR"/m]

    refute_nil block, "production deploy must use the fixed app-user sync path"
    assert_includes block, 'rails_sync_app_tree "$app_name" shared'
    assert_includes block, 'rails_sync_app_tree "$app_name" verticals'
    refute_match(/doas (?:rm|chown|mkdir|mv|sh -c)/, block)
    assert_includes sync, "/usr/local/libexec/rails-sync.ksh"
    refute_includes sync, "pub5-admin"
  end

  def test_deploy_does_not_prepare_or_install_a_bundle_on_vm23
    deploy = File.read(File.join(ROOT, "RAILS", "_deploy.sh"), encoding: "UTF-8")
    helper = File.read(File.join(ROOT, "OPENBSD", "mirror", "usr", "local", "libexec", "rails-task.ksh"), encoding: "UTF-8")
    refute_includes deploy, "bundle-cache-prepare"
    refute_includes deploy, "bundle_install_as_app"
    refute_includes helper, "bundle-cache-prepare)"
    # Bounded provisioning only (operator, 2026-11-25): niced, time-limited,
    # one job, frozen to the pinned lockfile.
    assert_includes helper[/^\s+bundle-install\)\n.*?;;/m].to_s, "nice -n 15 timeout 900"
    assert_includes deploy, '"bundle-check"'
  end

  def test_production_deploys_only_verify_the_preinstalled_bundle
    core = File.read(File.join(ROOT, "RAILS", "_bundle.sh"), encoding: "UTF-8")
    deploy = File.read(File.join(ROOT, "RAILS", "_deploy.sh"), encoding: "UTF-8")
    runtime = File.read(File.join(ROOT, "RAILS", "_runtime_check.sh"), encoding: "UTF-8")
    tasks = File.read(File.join(ROOT, "OPENBSD", "mirror", "usr", "local", "libexec", "rails-task.ksh"), encoding: "UTF-8")

    assert_equal 1, core.scan("bundle_install_as_app() {").length
    refute_includes deploy, "bundle_install_as_app"
    assert_includes deploy, '"bundle-check"'
    assert_includes runtime, '"bundle-check"'
    # Provisioning is allowed now (operator, 2026-11-25), but only bounded: niced,
    # time-limited, one job, and frozen to the pinned lockfile.
    install = tasks[/^\s+bundle-install\)\n.*?;;/m].to_s
    assert_includes install, "nice -n 15 timeout 900"
    refute_includes tasks, "ci-bundle-install)"
  end

  def test_relayd_adapter_is_read_only_and_fails_closed
    service = File.read(File.join(ROOT, "RAILS", "_service.sh"), encoding: "UTF-8")
    adapter = service[/relayd_add_relay\(\) \{.*?^\}/m]
    refute_nil adapter
    assert_includes adapter, "File.lstat(path)"
    assert_includes adapter, "relayd.conf must be a root-owned, non-writable regular file"
    refute_match(/\$\{_PRIV\}.*\$RUBY/, adapter)
    refute_includes adapter, "pub5-admin"
  end
  def test_rails_relayd_route_check_uses_the_installed_policy
    service = File.read(File.join(ROOT, "RAILS", "_service.sh"), encoding: "UTF-8")
    deploy = File.read(File.join(ROOT, "RAILS", "_deploy.sh"), encoding: "UTF-8")
    assert_includes service, 'path = "/etc/relayd.conf"'
    assert_includes service, "File.lstat(path)"
    assert_includes deploy, 'relayd_add_relay "$APP_NAME" "$APP_DOMAIN" "$APP_PORT"'
    probe = service[/post_restart_probe\(\) \{.*?^\}/m]
    refute_nil probe
    refute_match(/\$\{_PRIV\}.*\$RUBY/m, probe)
  end
  def test_app_secret_path_uses_atomic_native_writes
    database = File.read(File.join(ROOT, "RAILS", "_database.sh"), encoding: "UTF-8")
    secret_fn = database[/app_secret_for\(\) \{.*?^\}/m]
    refute_nil secret_fn
    assert_includes secret_fn, "SECRET_KEY_BASE="
    assert_includes secret_fn, "File.link(temporary, target)"
    assert_includes secret_fn, "File.chown(0, Etc.getgrnam(app).gid, temporary)"
    refute_includes secret_fn, "pub5-admin"
    refute_includes secret_fn, '"${_PRIV}" sh -c'
  end
  def test_secondary_database_probe_uses_the_fixed_app_task
    database = File.read(File.join(ROOT, "RAILS", "_database.sh"), encoding: "UTF-8")
    probe = database[/secondary_db_initialized\(\) \{.*?^\}/m]
    refute_nil probe
    assert_includes probe, '"secondary-db-check" "$db"'
    refute_match(/\$\{_PRIV\} sh -c/, probe)
    refute_match(/\$\{_PRIV\} cat/, probe)
  end
  def test_storage_migration_uses_the_fixed_app_task
    database = File.read(File.join(ROOT, "RAILS", "_database.sh"), encoding: "UTF-8")
    migration = database[/migrate_sqlite_db_to_storage_if_needed\(\) \{.*?^\}/m]
    refute_nil migration
    assert_includes migration, 'run_rails_as_app "$app_name" "$app_dir" "db-storage-migrate"'
    refute_match(/\$\{_PRIV\}\s+(?:mkdir|mv|chown)\b/, migration)
    refute_includes migration, "pub5-admin"
  end
  def test_rails_database_tasks_use_closed_dispatcher
    database = File.read(File.join(ROOT, "RAILS", "_database.sh"), encoding: "UTF-8")
    runtime = File.read(File.join(ROOT, "RAILS", "_runtime_check.sh"), encoding: "UTF-8")

    assert_includes database, 'run_rails_as_app "$app_name" "$app_dir" "db-prepare"'
    assert_includes database, 'run_rails_as_app "$app_name" "$app_dir" "schema-load" "$db"'
    assert_includes database, 'run_rails_as_app "$app_name" "$app_dir" "secondary-db-check" "$db"'
    assert_includes database, 'run_rails_as_app "$app_name" "$app_dir" "db-storage-migrate"'
    assert_includes database, 'run_rails_as_app "$app_name" "$app_dir" "db-seed"'
    assert_includes database, 'run_rails_as_app "$app_name" "$app_dir" "demo-seed"'
    assert_includes runtime, 'rails-task.ksh "$app_name" "$task" "$database"'
  end

  def test_rails_deploy_never_installs_rcd_from_writable_checkout
    service = File.read(File.join(ROOT, "RAILS", "_service.sh"), encoding: "UTF-8")

    refute_includes service, '${_PRIV} install -o root -g wheel -m 0555 "$rcd_src" "$rcd_dst"'
    assert_includes service, 'owner=$(/usr/bin/stat -f %u "$rcd_dst")'
    assert_includes service, 'mode=$(/usr/bin/stat -f %Lp "$rcd_dst")'
    assert_includes service, 'rc.d ${svc} must be root-owned mode 555'
    assert_includes service, 'retire_legacy_rails_rcd "$app_name"'
    refute_includes service, "pub5-admin"
  end

  def test_rails_service_adapter_uses_native_rcctl
    core = File.read(File.join(ROOT, "RAILS", "_core.sh"), encoding: "UTF-8")
    adapter = core[/pub4_rcctl\(\) \{.*?^\}/m]

    refute_nil adapter
    assert_includes adapter, '"${_PRIV}" /usr/sbin/rcctl "$action" "$service"'
    refute_includes adapter, "pub5-admin"
    refute_match(/\$\{_PRIV\}\s+rcctl\b/, adapter)
  end

  def test_rails_deploy_service_lifecycle_uses_native_rcctl
    core = File.read(File.join(ROOT, "RAILS", "_core.sh"), encoding: "UTF-8")
    deploy = File.read(File.join(ROOT, "RAILS", "_deploy.sh"), encoding: "UTF-8")

    assert_includes core, "pub4_rcctl() {"
    assert_includes core, "check|get|start|stop|restart"
    assert_includes core, '"${_PRIV}" /usr/sbin/rcctl "$action" "$service"'
    assert_includes deploy, 'pub4_rcctl stop "$app_name"'
    assert_includes deploy, 'pub4_rcctl restart "$APP_NAME" || pub4_rcctl start "$APP_NAME"'
    refute_includes deploy, 'doas rcctl stop "$app_name"'
    refute_includes deploy, "pub5-admin"
  end

  def test_rails_app_deploy_wrappers_refuse_root_execution
    %w[brgen amber bsdports].each do |app|
      source = File.read(File.join(ROOT, "RAILS", app, "#{app}.sh"), encoding: "UTF-8")
      assert_includes source, 'if [[ $(id -u) -eq 0 ]]', "#{app} wrapper must refuse root"
      assert_includes source, 'refusing to run checkout code as root', "#{app} refusal should be explicit"
    end
  end

  def test_legacy_rails_entrypoint_never_escalates_checkout_code
    legacy = File.read(File.join(ROOT, "RAILS", "deploy.sh"), encoding: "UTF-8")

    assert_includes legacy, 'if [[ $(id -u) -eq 0 ]]'
    assert_includes legacy, 'exec zsh "${REPO_ROOT}/OPENBSD/bin/vps-deploy" "$app"'
    refute_includes legacy, 'doas zsh "$script"'
  end

  def test_ci_source_permissions_do_not_grant_world_read
    prepare_path = File.join(ROOT, "OPENBSD", "mirror", "usr", "local", "libexec", "ci-prepare.ksh")
    prepare = File.read(prepare_path, encoding: "UTF-8")
    refute_match(/chmod\b[^\n]*\b(?:a|o)r/, CI_SOURCE, "vps_ci.sh must not grant world read")
    refute_match(/chmod\b[^\n]*\b(?:a|o)r/, prepare, "ci-prepare.ksh must not grant world read")
    assert_includes prepare, "/bin/chmod 750 /home/dev"
    runtime_check = File.read(File.join(ROOT, "RAILS", "_runtime_check.sh"), encoding: "UTF-8")
    refute_match(/chmod\b[^\n]*\b(?:a|o)\+r/, runtime_check, "_runtime_check.sh must not grant world read")
  end

  def test_ci_does_not_escalate_permission_changes_on_the_checkout
    refute_match(/doas\s+(?:\S+\/)?chmod\b/, CI_SOURCE, "permission changes belong to ci-prepare.ksh, not a doas chmod")
    assert_source CI_SOURCE, 'doas /usr/local/libexec/ci-prepare.ksh "$app"'
  end

  def test_ci_helpers_are_installed_and_used_before_sync
    operator = File.read(File.join(ROOT, "OPENBSD", "OPERATOR.sh"), encoding: "UTF-8")

    # OPERATOR.sh installs every Git-tracked mirror file individually. The old
    # recursive tree copy belonged to BOOTSTRAP.sh and bypassed per-file owner,
    # mode, backup and read-back verification.
    assert_includes operator, 'ls-files -z -- OPENBSD/mirror'
    assert_includes operator, 'install_one "$rel"'
    assert_includes operator, 'install -o "$owner" -g "$group" -m "$mode" "$source_file" "$tmp"'
    refute_includes operator, 'cp -R "$src/$d"/. "/$d"/'

    helpers = Dir.glob(File.join(ROOT, "OPENBSD", "mirror", "usr", "local", "libexec", "*"))
                   .map { |path| path.delete_prefix("#{ROOT}/") }.sort
    tracked, status = Open3.capture2("git", "-C", ROOT, "ls-files", "--error-unmatch", *helpers)
    assert status.success?, "OpenBSD libexec helpers must be tracked mirror files"
    assert_equal helpers, tracked.lines.map(&:chomp).sort

    assert_source CI_SOURCE, 'doas /usr/bin/su -m "$app" -c "/usr/local/libexec/ci-sync.ksh $app"'
    assert_operator CI_SOURCE.index('doas /usr/local/libexec/ci-prepare.ksh "$app"'),
                    :<, CI_SOURCE.index("sync_from_repo\n")
  end

  def test_ci_copy_tree_uses_the_app_scoped_helper
    assert_source CI_SOURCE, 'doas /usr/bin/su -m "$app" -c "/usr/local/libexec/ci-sync.ksh $app"'
    refute_source CI_SOURCE, "sync_from_repo_legacy"
    refute_source CI_SOURCE, "sync_ci_rails_root_legacy"
    assert_source CI_SOURCE, "unaccounted_tracked_files \"$app\" \"$repo\" paths kept_local"
    assert_operator CI_SOURCE.index('doas /usr/local/libexec/ci-prepare.ksh "$app"'),
                    :<, CI_SOURCE.index("sync_from_repo\n")
  end

  def test_ci_has_no_broker_and_no_root_copy_fallback
    refute_source CI_SOURCE, "pub5-admin"
    refute_match(/doas\s+(?:sh\s+-c|(?:rm|mkdir|chown|chmod|tee|groupadd|usermod|tar)\b)/, CI_SOURCE)
    refute_source CI_SOURCE, "sync_from_repo_legacy"
  end
  def test_ci_runner_is_retired_on_the_production_host
    runner = File.read(File.join(ROOT, "OPENBSD", "mirror", "usr", "local", "libexec", "ci-run.ksh"), encoding: "UTF-8")
    assert_includes runner, "refused"
    assert_includes runner, "workstation"
    assert_includes runner, "exit 69"
    refute_match(/^(?!echo\b)[^#\n]*\bbin\/ci\b/, runner, "ci-run.ksh must refuse, never run bin/ci")
    refute_source CI_SOURCE, "ci-run.ksh"
  end

  def test_ci_uses_the_helper_for_account_and_storage_preparation
    assert_source CI_SOURCE, 'doas /usr/local/libexec/ci-prepare.ksh "$app"'
    refute_source CI_SOURCE, "pub5-admin"
    refute_match(/doas\s+(?:sh\s+-c|(?:rm|mkdir|chown|chmod|tee|groupadd|usermod|tar)\b)/, CI_SOURCE)
  end

  # Since 2026-10-28 the deploy runs as root and re-execs itself through
  # passwordless doas. Root has no github.com host key by design, so every git
  # call must still go through the unprivileged deploy user.
  # The helper may sync only after the parent has pinned and admitted the
  # exact commit and supplied workstation CI/preflight attestations.
  def test_a_ci_attestation_covers_exactly_the_commit_it_names
    assert_source SOURCE, %q{[[ ${VPS_DEPLOY_CI_SHA:-} == "$pin" ]]}
    assert_source CI_SOURCE, %q{head=$(git_as_deploy_user rev-parse HEAD 2>/dev/null)}
    assert_source CI_SOURCE, "git_as_deploy_user() {"
    assert_source CI_SOURCE, "run_as_deploy_user"
    refute_source CI_SOURCE, %q{git -C "$repo"}
    assert_source CI_SOURCE, %q{[[ ${VPS_DEPLOY_LOCK_HELD:-} == 1}
    assert_source CI_SOURCE, %q{owner_identity == "$VPS_DEPLOY_LOCK_IDENTITY"}
    assert_source CI_SOURCE, %q{${owner_started}_${owner_digest} == "$owner_identity"}
    assert_source CI_SOURCE, %q{[[ ${VPS_DEPLOY_SHA:-} == "$head" ]]}
    assert_source CI_SOURCE, %q{[[ $attested == "$head" ]]}
    assert_source CI_SOURCE, %q{[[ ${VPS_DEPLOY_ADMITTED_SHA:-} == "$head" ]]}
    assert_source CI_SOURCE, %q{if [[ -n ${VPS_DEPLOY_PREFLIGHT_SHA:-} ]]; then}
    assert_source CI_SOURCE, "workstation preflight SHA does not match"
    assert_source CI_SOURCE, %q{VPS_DEPLOY_SKIP_PREFLIGHT:-0}
    sync = CI_SOURCE.index("sync_from_repo" + "\n")
    %w[VPS_DEPLOY_LOCK_HELD VPS_DEPLOY_SHA VPS_DEPLOY_CI_SHA VPS_DEPLOY_ADMITTED_SHA VPS_DEPLOY_PREFLIGHT_SHA].each do |name|
      position = CI_SOURCE.index(name)
      refute_nil position, "missing #{name} guard"
      assert_operator position, :<, sync, "#{name} must be checked before copy-tree sync"
    end
    assert_source CI_SOURCE, %q{"bundle-check"}
    refute_source CI_SOURCE, "ci-run.ksh"
    refute_source CI_SOURCE, "bundle_install_as_app"
    refute_source CI_SOURCE, "VPS_DEPLOY_SKIP_TESTS"
    refute_source SOURCE, "SKIP_CI=1"
    refute_source SOURCE, "preflight-boot"
    refute_source SOURCE, 'canary.rb" --no-rehearse'
  end

  def test_the_ci_stamp_only_records_a_workstation_attestation
    assert_source CI_SOURCE, "ci_stamp=ci_attested"
    refute_source CI_SOURCE, "ci_stamp=ci_ok"
    refute_source CI_SOURCE, "ci_stamp=ci_skipped"
    assert_source CI_SOURCE, 'status == "ci_attested"'
    assert_source CI_SOURCE, %q{doas "$RUBY" -rjson}
  end

  def test_it_runs_as_root_and_keeps_git_as_the_deploy_user
    guard = SOURCE[/if \[\[ \$\(id -u\) -ne 0 \]\]; then.*?^fi$/m]

    refute_nil guard, "the uid gate is gone"
    assert_includes guard, 'exec doas -n /usr/bin/env "${deploy_env[@]}" zsh "$self" "$@"'
    assert_match(/exit 2/, guard, "without doas the gate must exit, not continue unprivileged")
    assert_source SOURCE, 'su -s /bin/sh "$DEPLOY_USER" -c "$snippet"'
    refute_match(/^\s*git\s+(?:-C\s+\S+\s+)?(?:fetch|pull|checkout|merge|reset)\b/, SOURCE,
                 "a bare git call runs as root, which cannot reach github")
  end

  # All selected Rails suites must pass on the workstation before SSH; vm23
  # checks only the immutable production bundle and the staged asset attestation.
  def test_no_skip_ci_bypass_exists
    refute_source SOURCE, "SKIP_CI"
    assert_source SOURCE, '[[ ${VPS_DEPLOY_CI_SHA:-} == "$pin" ]]'
    assert_source CI_SOURCE, '[[ $attested == "$head" ]]'
  end

  def test_the_deploy_flag_is_held_for_the_whole_deploy_and_released_on_exit
    refute_nil flag_block, "the deploy flag block is gone - the scan broke, or the flag did"
    guard_glob = GUARD[%r{^DEPLOY_FLAGS="(/home/dev/pub5/\.deploying\S*)"$}, 1]
    assert_source GUARD, "for _flag in $DEPLOY_FLAGS; do", "the guard no longer loops over DEPLOY_FLAGS"
    refute_nil guard_glob, "resource_guard no longer reads a deploy flag glob"

    Dir.mktmpdir do |repo|
      # log() lives above the extracted block; without a stub the EXIT trap's
      # log call resolves to zsh's own `log` builtin (zsh/watch module), which
      # rejects arguments and leaks "too many arguments" onto the runner's stderr.
      script = "repo=#{repo}; app=bsdports; deploy_log=#{repo}/deploy.log\nrelease_deploy_lock() { :; }\nlog() { :; }\n#{flag_block}\nhold_deploy_flag\nprint -r -- $deploy_flag\n[[ -e $deploy_flag ]] && print held\n"
      out = IO.popen(["zsh", "-c", script], &:read).lines.map(&:chomp)
      flag = out.first

      assert_equal "held", out.last, "the flag is not on disk while the deploy runs"
      assert File.fnmatch?(guard_glob.sub("/home/dev/pub5", repo), flag, File::FNM_DOTMATCH),
             "#{flag} is not a name resource_guard's #{guard_glob} reads"
      refute File.exist?(flag), "the flag outlived the script, so shedding stays off for 30 minutes"

      rcd_flag = File.read(File.join(ROOT, "OPENBSD", "mirror", "etc", "rc.d", "bsdports"), encoding: "UTF-8")[%r{touch \S+/(\.deploying\S*)}, 1]
      refute_equal rcd_flag, File.basename(flag),
                   "rc.d removes its own flag after /up, so sharing its name drops the hold mid-deploy"
    end
  end

  # A source-contract miss names the snippet; assert_includes printed all of
  # vps-deploy (70 KB) into the rehearsal and buried the failing line.
  def assert_source(source, snippet, message = nil)
    assert source.include?(snippet), message || "source lacks #{snippet.inspect}"
  end

  def refute_source(source, snippet, message = nil)
    refute source.include?(snippet), message || "source still contains #{snippet.inspect}"
  end

  def flag_block
    SOURCE[/^deploy_flag=.*?^trap 'exit 143' TERM$/m]
  end

  def lock_block
    SOURCE[/^lock_dir=.*?(?=^# Deployment transcripts belong on the workstation)/m]
  end

  # Runs the lock block alone in zsh against a scratch directory; returns [output, exit status].
  def lock_run(dir, ttl: 7200, body: "print acquired")
    script = "export VPS_DEPLOY_LOCK_DIR=#{dir}/deploy.lock VPS_DEPLOY_LOCK_TTL=#{ttl}\n#{lock_block}\n#{body}\n"
    out = IO.popen(["zsh", "-c", script, { err: %i[child out] }], &:read)
    [out, $?.exitstatus]
  end

  def lock_process_identity(pid)
    started, started_status = Open3.capture2({ "LC_ALL" => "C" }, "ps", "-p", pid.to_s, "-o", "lstart=")
    command, command_status = Open3.capture2("ps", "-ww", "-p", pid.to_s, "-o", "command=")
    return unless started_status.success? && command_status.success?

    checksum, checksum_status = Open3.capture2("cksum", stdin_data: command.chomp)
    return unless checksum_status.success?

    # $(...) strips only trailing newlines: keep ps's padding as the deployer does.
    normalized_start = started.sub(/\n+\z/, "").gsub(/[^A-Za-z0-9]/, "_")
    normalized_checksum = checksum.split.join("_")
    "#{normalized_start}_#{normalized_checksum}"
  end

  def test_inherited_child_flag_cannot_bypass_parent_lock_identity
    refute_nil lock_block
    assert_includes lock_block, "lock_read_owner ||"
    assert_includes lock_block, "VPS_DEPLOY_LOCK_PID"
    assert_includes lock_block, "VPS_DEPLOY_LOCK_IDENTITY"
    assert_includes lock_block, "current_identity == \"$lock_identity\""

    Dir.mktmpdir do |dir|
      script = "export VPS_DEPLOY_LOCK_DIR=#{dir}/deploy.lock VPS_DEPLOY_LOCK_HELD=1\n#{lock_block}\nprint acquired\n"
      out = IO.popen(["zsh", "-c", script, { err: %i[child out] }], &:read)
      refute_equal 0, $?.exitstatus
      assert_includes out, "child invocation has no readable parent lock owner"
      refute_includes out, "acquired"
    end
  end

  def test_a_lock_records_its_owner_and_is_released_on_exit
    refute_nil lock_block, "the lock block is gone - the scan broke, or the lock did"
    Dir.mktmpdir do |dir|
      out, status = lock_run(dir, body: "print -r -- $(<$lock_dir/owner)\nrelease_deploy_lock")
      pid, host, epoch, identity = out.lines.last.split

      assert_equal 0, status
      assert_match(/\A\d+\z/, pid)
      assert_equal Socket.gethostname.split(".").first, host
      assert_in_delta Time.now.to_i, epoch.to_i, 30
      assert_match(/\A[A-Za-z0-9_]+\z/, identity)
      refute Dir.exist?(File.join(dir, "deploy.lock")), "release left the lock behind"
    end
  end

  def test_a_matching_live_process_fingerprint_keeps_its_lock
    identity = lock_process_identity(Process.pid)
    skip "ps does not expose a process fingerprint here" unless identity

    Dir.mktmpdir do |dir|
      lock = File.join(dir, "deploy.lock")
      Dir.mkdir(lock)
      owner = "#{Process.pid} #{Socket.gethostname.split(".").first} #{Time.now.to_i - 9000} #{identity}\n"
      File.write(File.join(lock, "owner"), owner)
      out, status = lock_run(dir)

      assert_equal 75, status
      assert_includes out, "another deploy owns"
      refute_includes out, "reaping stale lock"
      assert_equal owner, File.read(File.join(lock, "owner"))
    end
  end

  def test_a_lock_whose_pid_is_gone_is_reaped_and_reported
    Dir.mktmpdir do |dir|
      lock = File.join(dir, "deploy.lock")
      Dir.mkdir(lock)
      File.write(File.join(lock, "owner"), "999999 #{Socket.gethostname.split(".").first} #{Time.now.to_i}\n")
      out, status = lock_run(dir)

      assert_equal 0, status
      assert_includes out, "reaping stale lock"
      assert_includes out, "owner pid 999999 is not running"
      assert_includes out, "acquired"
    end
  end

  def test_a_reused_pid_does_not_keep_an_abandoned_lock_alive
    Dir.mktmpdir do |dir|
      lock = File.join(dir, "deploy.lock")
      Dir.mkdir(lock)
      owner = "#{Process.pid} #{Socket.gethostname.split(".").first} #{Time.now.to_i - 9000} old_process_started_identity_123_45\n"
      File.write(File.join(lock, "owner"), owner)
      out, status = lock_run(dir)

      assert_equal 0, status
      assert_includes out, "process identity changed"
      assert_includes out, "PID reused"
      assert_includes out, "acquired"
    end
  end

  def test_stale_lock_recovery_does_not_touch_a_lock_claimed_by_another_reaper
    Dir.mktmpdir do |dir|
      lock = File.join(dir, "deploy.lock")
      Dir.mkdir(lock)
      owner = "999999 #{Socket.gethostname.split(".").first} #{Time.now.to_i}\n"
      File.write(File.join(lock, "owner"), owner)
      Dir.mkdir(File.join(lock, "reaping"))

      out, status = lock_run(dir)

      assert_equal 75, status
      assert_includes out, "another deploy owns"
      assert_equal owner, File.read(File.join(lock, "owner")),
                   "a competing reaper must not remove the original owner's record"
      assert Dir.exist?(File.join(lock, "reaping")),
             "the first reaper's claim must remain untouched"
    end
  end

  def test_two_simultaneous_stale_lock_reapers_never_both_acquire
    Dir.mktmpdir do |dir|
      lock = File.join(dir, "deploy.lock")
      barrier = File.join(dir, "reapers-ready")
      Dir.mkdir(lock)
      File.write(File.join(lock, "owner"), "999999 #{Socket.gethostname.split(".").first} #{Time.now.to_i}\n")

      observed_lock = 'before_identity=$(file_identity "$lock_dir") || return 1'
      barrier_step = <<~'ZSH'
        # $(<file) drops the trailing newline, so two pids read back with one.
        print -r -- "$$" >> "$VPS_DEPLOY_TEST_BARRIER"
        local -i waited=0
        while [[ $(<"$VPS_DEPLOY_TEST_BARRIER") != *$'\n'* ]] && (( waited < 200 )); do
          sleep 0.01
          (( waited += 1 ))
        done
        [[ $(<"$VPS_DEPLOY_TEST_BARRIER") == *$'\n'* ]] || return 1
        OBSERVED_LOCK
      ZSH
      barrier_step = barrier_step.sub("OBSERVED_LOCK", observed_lock).strip
      racing_block = lock_block.sub(observed_lock, barrier_step)
      refute_equal lock_block, racing_block, "the two-process barrier did not attach to stale-lock recovery"

      output_paths = 2.times.map { |i| File.join(dir, "reaper-#{i}.log") }
      pids = output_paths.each_with_index.map do |output_path, i|
        script = "#{racing_block}\nsleep 0.2\nprint -r -- acquired-#{i}\n"
        Process.spawn(
          {
            "VPS_DEPLOY_LOCK_DIR" => lock,
            "VPS_DEPLOY_LOCK_TTL" => "7200",
            "VPS_DEPLOY_TEST_BARRIER" => barrier,
          },
          "zsh", "-c", script,
          out: output_path, err: [:child, :out]
        )
      end
      statuses = pids.map { |pid| Process.wait2(pid).last.exitstatus }
      outputs = output_paths.map { |path| File.read(path) }

      assert_equal [0, 75], statuses.sort, outputs.inspect
      assert_equal 1, outputs.count { |out| out.match?(/acquired-\d/) },
                   "exactly one deploy may acquire the lock after simultaneous stale observations"
    end
  end

  def test_a_live_local_owner_is_not_reaped_just_because_the_ttl_elapsed
    Dir.mktmpdir do |dir|
      lock = File.join(dir, "deploy.lock")
      Dir.mkdir(lock)
      owner = "#{Process.pid} #{Socket.gethostname.split(".").first} #{Time.now.to_i - 9000}\n"
      File.write(File.join(lock, "owner"), owner)
      out, status = lock_run(dir)

      assert_equal 75, status
      assert_includes out, "another deploy owns"
      assert_equal owner, File.read(File.join(lock, "owner")), "a live owner's stale timestamp must not let a second deploy steal its lock"
    end
  end

  def test_a_live_fresh_lock_refuses_the_second_deploy
    Dir.mktmpdir do |dir|
      lock = File.join(dir, "deploy.lock")
      Dir.mkdir(lock)
      owner = "#{Process.pid} #{Socket.gethostname.split(".").first} #{Time.now.to_i}\n"
      File.write(File.join(lock, "owner"), owner)
      out, status = lock_run(dir)

      assert_equal 75, status
      assert_includes out, "another deploy owns"
      assert_equal owner, File.read(File.join(lock, "owner")), "a live owner's record was disturbed"
    end
  end

  def test_a_bare_fresh_lock_directory_is_left_alone_and_a_stale_one_is_reaped
    Dir.mktmpdir do |dir|
      lock = File.join(dir, "deploy.lock")
      Dir.mkdir(lock)
      File.write(File.join(lock, "owner.tmp.123"), "partial owner record\n")
      _out, status = lock_run(dir)
      assert_equal 75, status

      File.utime(Time.now - 9000, Time.now - 9000, lock)
      out, status = lock_run(dir)
      assert_equal 0, status
      assert_includes out, "no readable owner"
      assert_empty Dir.glob(File.join(dir, "deploy.lock.stale.*")),
                   "reaping must remove an interrupted atomic owner-write temporary"
    end
  end

  def test_the_flag_is_taken_before_ci_and_the_app_is_checked_before_ok
    assert_operator SOURCE.index("\nkeep_deploy_flag\n"), :<, SOURCE.index("OPENBSD/bin/vps_ci.sh")
    assert_operator SOURCE.index("kill $flag_keeper"), :<, SOURCE.index(%(rm -f -- "$deploy_flag"))
    assert_operator SOURCE.rindex(%(admin_service check "$app")), :>, SOURCE.index(%(CHECK_AUTOFIX=0 "$RUBY" "$repo/MASTER/checks/runner.rb"))
  end

  def test_a_master_deploy_holds_the_flag_before_its_build
    flag_call = SOURCE.index("\n  keep_deploy_flag\n")
    build_call = SOURCE.index('if zsh "$repo/OPENBSD/bin/vps_deploy_master.sh"')

    refute_nil flag_call
    refute_nil build_call
    assert_operator flag_call, :<, build_call, "master's build runs before its deploy flag is kept"
  end

  # The copy-tree on vm23 keeps path gems where the Gemfiles name them: __shared
  # beside app/ (synced by ci-sync), and brgen's vertical engines inside the app
  # tree at engines/ (the copy-tree's rel list carries them). The layout moved
  # twice (shared became __shared, then the sibling brgen_* directories moved
  # inside brgen as engines/) and the CI mirror kept building the old one until
  # a deploy died on "The path /home/brgen/__shared does not exist".
  def test_ci_mirror_syncs_every_path_gem_the_gemfiles_name
    ci = File.read(File.join(ROOT, "OPENBSD", "bin", "vps_ci.sh"), encoding: "UTF-8")
    sync = File.read(File.join(ROOT, "OPENBSD", "mirror", "usr", "local", "libexec", "ci-sync.ksh"), encoding: "UTF-8")
    assert_includes sync, "shared_dir=$app_home/__shared"
    assert_includes sync, "for rel in test app lib config bin db engines public vendor/javascript"
    assert_includes ci, '"bundle-check"'
    refute_includes ci, "ci_timeout="
    refute_includes ci, "ci-run.ksh"
    assert_includes sync, '[ -d "$src/engines" ] || rm -rf "$app_dir/engines"'

    (APPS - ["master"]).each do |app|
      gemfile = File.join(ROOT, "RAILS", app, "Gemfile")
      next unless File.file?(gemfile)

      File.read(gemfile, encoding: "UTF-8").scan(/path:\s*"([^"]+)"/).flatten.uniq.each do |ref|
        if ref.start_with?("../")
          assert ref == "../__shared",
                 "#{app}/Gemfile names #{ref}, which vps_ci.sh does not sync beside app/"
        else
          assert File.directory?(File.join(ROOT, "RAILS", app, ref)),
                 "#{app}/Gemfile names #{ref}, which is not in the app tree the copy-tree carries"
        end
      end
    end
  end

  def test_the_deploy_has_exactly_one_terminal_finish_definition_and_exit_trap
    assert_equal 1, SOURCE.scan(/^finish\(\) \{/).size
    assert_equal 1, SOURCE.scan(/^trap finish EXIT$/).size
  end

  # The trap block alone, in zsh, with doas and write_stamp stubbed: what a failed
  # deploy says, stamps and leaves behind is the contract an operator reads at 3 a.m.
  def finish_block
    SOURCE[/^deploy_stage=start$.*?^trap 'exit 143' TERM$/m]
  end

  def finish_run(dir, body, down: "amber")
    log = File.join(dir, "deploy.log")
    script = <<~ZSH
      app=brgen; repo=#{dir}; deploy_log=#{log}; deploy_flag=#{dir}/.flag; lock_owner=1; DEPLOY_RAILS=(brgen amber bsdports)
      log() { print -r -- "$*"; }
      restore_started() { print restoring; }
      release_deploy_lock() { print released; }
      write_stamp() { stamp_written=1; print "stamp $1 $2"; }
      doas() { [[ $1 == rcctl && $2 == check && $3 == #{down} ]] && return 1; return 0; }
      admin_service() { doas rcctl "$@"; }
      #{finish_block}
      touch $deploy_flag
      #{body}
    ZSH
    out = IO.popen(["zsh", "-c", script, { err: %i[child out] }], &:read)
    [out, $?.exitstatus, File.exist?(log) ? File.read(log) : ""]
  end

  def test_a_failure_after_the_stop_stamps_failed_names_the_stage_and_what_is_down
    refute_nil finish_block, "the terminal-result block is gone - the scan broke, or the block did"
    Dir.mktmpdir do |dir|
      out, status, log = finish_run(dir, "deploy_stage=migrate; app_stopped=1; exit 1")

      assert_equal 1, status
      assert_includes out, "stamp brgen failed"
      assert_includes out, 'brgen FAILED at stage "migrate" (exit 1)'
      assert_includes out, "brgen was stopped for this deploy and is DOWN"
      assert_includes out, "doas /usr/sbin/rcctl start brgen"
      assert_includes out, "amber is DOWN"
      refute_includes out, "bsdports is DOWN"
      assert_includes out, "released"
      assert_match(/finished exit=1/, out)
      assert_empty log, "deployment transcripts must not be written to the VM filesystem"
      refute File.exist?(File.join(dir, ".flag")), "the deploy flag outlived the script"
    end
  end

  def test_a_failure_before_the_stop_says_the_previous_release_is_still_serving
    Dir.mktmpdir do |dir|
      out, status, = finish_run(dir, "deploy_stage=ci+sync; exit 3", down: "none")

      assert_equal 3, status
      assert_includes out, 'FAILED at stage "ci+sync" (exit 3)'
      assert_includes out, "was not stopped; the previous release is still serving"
      refute_includes out, "is DOWN"
    end
  end

  def test_a_stage_that_already_stamped_is_not_stamped_twice_and_success_is_logged_quietly
    Dir.mktmpdir do |dir|
      out, status, = finish_run(dir, "write_stamp brgen failed; exit 1")
      assert_equal 1, status
      assert_equal 1, out.scan("stamp brgen failed").size

      out, status, log = finish_run(dir, "deploy_stage=final-check; exit 0")
      assert_equal 0, status
      refute_includes out, "FAILED"
      assert_match(/finished exit=0/, out)
      assert_empty log, "successful deployments must not leave a remote transcript"
    end
  end

  def test_a_kill_or_a_dropped_session_is_a_recorded_failure_not_a_silent_end
    Dir.mktmpdir do |dir|
      %w[TERM HUP].each do |signal|
        out, status, log = finish_run(dir, "deploy_stage=precompile; kill -#{signal} $$; sleep 5")
        assert_equal({ "TERM" => 143, "HUP" => 129 }.fetch(signal), status, signal)
        assert_includes out, 'FAILED at stage "precompile"'
        assert_includes out, "finished exit="
        assert_empty log, "signal handling must not persist transcript files on vm23"
      end
    end
  end

  # `all` exits from its own loop; a trap installed after that branch never ran for
  # the parent, so every full deploy left its lock to the stale reaper.
  def test_the_terminal_trap_is_installed_before_the_all_branch_can_exit
    assert SOURCE.index("trap finish EXIT") < SOURCE.index("if [[ $deploy_target_kind == all ]]; then"),
           "the parent of `vps-deploy all` exits without releasing its lock"
  end

  def disk_block
    SOURCE[/^set_stage preflight-disk$.*?^done$/m]
  end

  # A diagnostic burst refused an unattended deploy outright (vm23, 2026-11-25):
  # pressure is waited out within the load gate's bound, then refused.
  def test_cpu_pressure_is_waited_out_within_the_load_bound
    wait = SOURCE[/^admit_cpu_pressure\(\) \{.*?^\}/m].to_s
    assert_includes wait, "VPS_DEPLOY_ADMISSION_WAIT:-900"
    assert_includes wait, "sleep 60"
    assert_includes wait, "deploy_refuse"
    pressure = SOURCE[/^active_cpu_pressure\(\) \{.*?^\}/m].to_s
    assert_includes pressure, "cpu-pressure"
    assert_includes pressure, "420 && pressure_busy >= 80"
    # The run's own pin/snapshot burst must not refuse it (vm23, 2026-11-25).
    assert_includes pressure, "pressure_stamp < started"
  end

  def test_deploy_admission_requires_two_low_load_and_swap_samples_without_cpu_pressure
    block = SOURCE[/^admit_host_load\(\) \{.*?^\}/m]
    refute_nil block, "the host admission gate is missing"
    assert_includes block, "for sample in 1 2"
    assert_includes block, "sleep 60"
    assert_includes block, "admit_load_five"
    load_gate = SOURCE[/^admit_load_five\(\) \{.*?^\}/m]
    refute_nil load_gate, "the five-minute load gate is missing"
    assert_includes load_gate, "< 2.0"
    assert_includes load_gate, "VPS_DEPLOY_ADMISSION_WAIT:-900"
    assert_includes SOURCE[/^read_load_five\(\) \{.*?^\}/m].to_s, "vm.loadavg"
    assert_includes block, "free_swap >= 400"
    assert_includes block, "admit_cpu_pressure"
    assert_source SOURCE, "admit_host_load"
    assert_source SOURCE, "VPS_DEPLOY_ADMITTED_SHA=$pin"
  end

  def test_fleet_admission_runs_once_before_mirror_and_children
    parent = SOURCE.index("if [[ $deploy_target_kind == all || $deploy_target_kind == group ]]; then")
    gate = SOURCE.index("  ensure_host_admission", parent)
    mirror = SOURCE.index('zsh "$repo/OPENBSD/OPERATOR.sh" --apply', parent)
    child = SOURCE.index('zsh "$0" "$one"', parent)

    refute_nil gate
    assert_operator gate, :<, mirror
    assert_operator gate, :<, child
    assert_source SOURCE, 'if [[ ${VPS_DEPLOY_ADMITTED_SHA:-} == "$pin" ]]; then'
    assert_source SOURCE, "resource shedding stays active"
  end

  # Deploy-time gem installs are allowed only bounded (operator, 2026-11-25).
  def test_deploy_time_gem_install_stays_bounded
    path = File.join(ROOT, "OPENBSD", "mirror", "usr", "local", "libexec", "rails-task.ksh")
    install = File.read(path, encoding: "UTF-8")[/^\s+bundle-install\)\n.*?;;/m].to_s

    assert_includes install, "nice -n 15 timeout 900"
    # Bundler 4 removed --frozen; vm23 re-execs into it from the lockfile.
    assert_includes install, "BUNDLE_FROZEN=true nice -n 15"
    assert_includes install, "install --jobs 1"
    refute_includes install, "--frozen"
  end

  # c7c69d670 inverted the arity check, so every two-argument task, the only
  # shape run_rails_as_app sends, exited 64 on vm23 (2026-11-25). A non-root
  # run that passes the arity check stops at the root check with 77 instead.
  def test_two_argument_rails_tasks_pass_the_arity_check
    path = File.join(ROOT, "OPENBSD", "mirror", "usr", "local", "libexec", "rails-task.ksh")
    skip "ksh is not installed" unless File.executable?("/bin/ksh")
    skip "the root check cannot be observed as root" if Process.uid.zero?
    status = ->(*argv) { Open3.capture2e("/bin/ksh", path, *argv).last.exitstatus }

    %w[bundle-check bundle-sibling-hydrate bundle-install db-prepare].each do |task|
      assert_equal 77, status.call("bsdports", task), task
    end
    assert_equal 64, status.call("bsdports", "bundle-check", "extra")
  end

  # The helper's PATH has no /sbin, and a bare chown there failed sibling
  # hydration after copying one gemspec, leaving it root-owned (vm23, 2026-11-25).
  def test_rails_task_names_sbin_tools_absolutely
    helper = File.read(File.join(ROOT, "OPENBSD", "mirror", "usr", "local", "libexec", "rails-task.ksh"))
    assert_includes helper, "PATH=/usr/local/bin:/usr/bin:/bin"
    assert_empty helper.lines.grep(/(?<![\w\/])chown\s/), "chown lives in /sbin, outside the helper's PATH"
  end

  # An unchecked `rcctl restart relayd || true` in rc.d/master left relayd dead and every
  # site refusing HTTPS (2026-11-26). Each app restart now goes through one helper that
  # proves relayd is running and retries.
  # Shared::MobileAppRegistry reads apps.yml beside __shared; the shared sync must put it there.
  def test_the_shared_sync_installs_the_fleet_inventory_beside_shared
    sync = File.read(File.join(ROOT, "OPENBSD", "mirror", "usr", "local", "libexec", "rails-sync.ksh"))
    assert_includes sync, "    sync_tree_stage \"$rails_root/__shared\" \"$app_home/__shared\" no\n    sync_inventory\n"
    assert_includes sync, "target=$app_home/apps.yml"
    registry = File.read(File.join(ROOT, "RAILS", "__shared", "lib", "shared", "mobile_app_registry.rb"))
    assert_includes registry, 'CONFIG = File.join(ROOT, "apps.yml")'
  end

  def test_app_restarts_kick_relayd_through_the_checking_helper
    kick = File.read(File.join(ROOT, "OPENBSD", "mirror", "usr", "local", "libexec", "relayd-kick.ksh"))
    assert_includes kick, "/usr/sbin/rcctl check relayd"
    assert_match(/while \[\[ \$attempt -le 3 \]\]/, kick)

    %w[amber brgen bsdports master mrdamascy].each do |app|
      rc = File.read(File.join(ROOT, "OPENBSD", "mirror", "etc", "rc.d", app))
      assert_includes rc, "/usr/local/libexec/relayd-kick.ksh", app
      refute_match(/^\s*rcctl restart relayd/, rc, app)
    end
  end

  def test_vps_deploy_and_master_deployer_are_build_free
    master = File.read(File.join(ROOT, "OPENBSD", "bin", "vps_deploy_master.sh"), encoding: "UTF-8")
    rc = File.read(File.join(ROOT, "OPENBSD", "mirror", "etc", "rc.d", "master"), encoding: "UTF-8")
    tasks = File.read(File.join(ROOT, "OPENBSD", "mirror", "usr", "local", "libexec", "rails-task.ksh"), encoding: "UTF-8")
    runtime = File.read(File.join(ROOT, "RAILS", "_runtime_check.sh"), encoding: "UTF-8")

    refute_source SOURCE, "rails_assets_precompile_as_app"
    refute_source SOURCE, "ensure_smart_turn_assets"
    refute_includes master, "bundle install"
    refute_includes master, "assets:precompile"
    assert_includes master, ".pub5-build-sha"
    assert_equal 1, master.scan("rails db:prepare").size, "master deploy must prepare the database once"
    assert_equal 1, master.scan("master_web_assets").size, "master deploy must select the asset check once"
    assert_operator master.index("==> verify prebuilt assets"), :<, master.index("==> db prepare")
    assert_match(/if \[ -f "\$ROOT\/MASTER\/checks\/runner\.rb" \].*else.*MasterWebAssetsCheck/m, master)
    refute_includes rc, "assets:precompile"
    refute_includes rc, "assets:build_face"
    assert_includes rc, ".pub5-build-sha"
    refute_includes tasks, "ci-bundle-install)"
    refute_includes tasks, "assets-precompile)"
    refute_includes tasks, "ci)"
    assert_includes tasks, "bundle-check)"
    assert_includes tasks, 'command="BUNDLE_FROZEN=true $bundle check"'
    assert_includes runtime, "BUNDLE_FROZEN=true bundle_exec check"
    assert_includes master, %q{[[ ${VPS_DEPLOY_LOCK_HELD:-} == 1}
    assert_includes master, %q{owner_identity == "$VPS_DEPLOY_LOCK_IDENTITY"}
    assert_includes master, %q{head=$(/usr/bin/su -s /bin/sh "$deploy_user" -c "cd /home/dev/pub5 && git rev-parse HEAD")}
    refute_includes master, "head=$(git rev-parse HEAD)"
    assert_includes master, "workstation preflight SHA does not match"
  end

  def test_legacy_fast_deploy_entrypoints_refuse_on_vm23
    manual = File.read(File.join(ROOT, "OPENBSD", "bin", "manual_master_deploy.ksh"), encoding: "UTF-8")
    fast = File.read(File.join(ROOT, "OPENBSD", "bin", "vps_production_push.sh"), encoding: "UTF-8")
    assert_includes manual, "exit 69"
    assert_includes fast, "exit 69"
    refute_includes manual, "pkill"
    refute_includes manual, "assets:precompile"
    refute_includes fast, "SKIP_CI=1"
    refute_includes fast, "SKIP_RUNTIME_CHECK=1"
  end

  def disk_run(dir, free_kb:)
    File.write(File.join(dir, "df"), "#!/bin/sh\nprintf 'Filesystem 1024-blocks Used Available Capacity Mounted on\\n/dev/sd0k 17000000 1000 #{free_kb} 80%% %s\\n' \"$2\"\n")
    File.chmod(0o755, File.join(dir, "df"))
    File.write(File.join(dir, "df"), "#!/bin/sh\nfor last; do :; done\nprintf 'Filesystem 1024-blocks Used Available Capacity Mounted on\\n/dev/x 17000000 1000 #{free_kb} 80%% %s\\n' \"$last\"\n")
    script = "app=brgen; VPS_DEPLOY_DF=#{dir}/df; set_stage() { :; }\n#{disk_block}\nprint passed\n"
    out = IO.popen(["zsh", "-c", script, { err: %i[child out] }], &:read)
    [out, $?.exitstatus]
  end

  def test_a_nearly_full_filesystem_refuses_the_deploy_before_anything_is_stopped
    refute_nil disk_block, "the disk preflight is gone - the scan broke, or the check did"
    Dir.mktmpdir do |dir|
      out, status = disk_run(dir, free_kb: 200_000)

      assert_equal 1, status
      assert_includes out, "/home has 195 MB free, the floor is 1024 MB"
      assert_includes out, "Nothing was stopped"
      assert_includes out, "zsh OPENBSD/bin/vps-deploy brgen"
      refute_includes out, "passed"
    end
  end

  def test_enough_free_space_lets_the_deploy_continue
    Dir.mktmpdir do |dir|
      out, status = disk_run(dir, free_kb: 4_000_000)

      assert_equal 0, status, out
      assert_includes out, "passed"
    end
  end

  def test_unavailable_disk_measurement_refuses_the_deploy_before_anything_is_stopped
    Dir.mktmpdir do |dir|
      out, status = disk_run(dir, free_kb: "unavailable")

      assert_equal 1, status
      assert_includes out, "free-space measurement for /home is unavailable"
      assert_includes out, "Nothing was stopped"
      refute_includes out, "passed"
    end
  end
  def deploy_setting_result(value, minimum:, maximum:)
    validator = SOURCE[/^validate_deploy_setting\(\) \{.*?^\}/m]
    refute_nil validator, "the deploy setting validator is missing"
    script = <<~ZSH
      #{validator}
      validate_deploy_setting TEST_SETTING "$TEST_VALUE" #{minimum} #{maximum}
    ZSH
    out, status = Open3.capture2e({ "TEST_VALUE" => value }, "zsh", "-c", script)
    [out, status.exitstatus]
  end

  def test_deploy_timing_overrides_reject_zero_negative_and_nondecimal_values
    ["0", "-1", "1.5", "1e3", "01", "", "999999999999999999999"].each do |value|
      out, status = deploy_setting_result(value, minimum: 1, maximum: 60)
      refute_equal 0, status, "accepted invalid timing value #{value.inspect}"
      assert_includes out, "invalid TEST_SETTING"
    end
  end

  def test_deploy_capacity_threshold_allows_only_bounded_decimal_percentages
    out, status = deploy_setting_result("0", minimum: 0, maximum: 100)
    assert_equal 0, status, out
    out, status = deploy_setting_result("100", minimum: 0, maximum: 100)
    assert_equal 0, status, out
    ["-1", "101", "10x", "010"].each do |value|
      out, status = deploy_setting_result(value, minimum: 0, maximum: 100)
      refute_equal 0, status, "accepted invalid percentage #{value.inspect}"
      assert_includes out, "invalid TEST_SETTING"
    end
  end

  def test_every_environment_driven_wait_and_capacity_setting_is_validated_before_locking
    %w[
      VPS_DEPLOY_LOCK_TTL
      VPS_DEPLOY_RESTORE_WAIT
      VPS_DEPLOY_POLL
      VPS_DEPLOY_SETTLE_WAIT
      VPS_DEPLOY_MASTER_MIN_AVAIL
      VPS_DEPLOY_MIN_FREE_KB
    ].each do |name|
      assert_source SOURCE, "validate_deploy_setting #{name}", "#{name} can influence arithmetic without validation"
    end

    assert_operator SOURCE.index("validate_deploy_setting VPS_DEPLOY_LOCK_TTL"),
                    :<, SOURCE.index("acquire_deploy_lock"),
                    "invalid environment must be rejected before a deployment lock is created"
  end

  def test_each_rails_deploy_proves_app_health_after_its_restart
    service = File.read(File.join(ROOT, "RAILS", "_service.sh"), encoding: "UTF-8")
    deploy = File.read(File.join(ROOT, "RAILS", "_deploy.sh"), encoding: "UTF-8")
    probe = service[/post_restart_probe\(\) \{.*?^\}/m]
    refute_nil probe
    assert_includes probe, 'http://127.0.0.1:${app_port}/up'
    assert_includes deploy, 'post_restart_probe "$APP_NAME" "$APP_PORT"'

    restart = deploy.index('pub4_rcctl restart "$APP_NAME" || pub4_rcctl start "$APP_NAME"')
    health = deploy.index('post_restart_probe "$APP_NAME" "$APP_PORT"')
    done = deploy.index('deploy_status "$app_name" "done" "done"')
    assert_operator restart, :<, health
    assert_operator health, :<, done
  end

  def test_master_restore_failure_is_stamped_failed_before_ok
    master = SOURCE.index("set_stage master-canary")
    restore = SOURCE.index("set_stage restore-shed", master)
    failed = SOURCE.index('write_stamp "$app" failed', restore)
    success = SOURCE.index('write_stamp "$app" ok', restore)

    refute_nil restore
    refute_nil failed
    refute_nil success
    assert_operator failed, :<, success
  end

  def test_rails_restore_failure_is_stamped_failed_before_ok
    canary = SOURCE.index('if ! "$RUBY" "$repo/OPENBSD/bin/canary" --local --app "$app"')
    restore = SOURCE.index("if (( restore_failed ))", canary)
    failed = SOURCE.index('write_stamp "$app" failed', restore)
    success = SOURCE.index('write_stamp "$app" ok', restore)

    refute_nil canary
    refute_nil restore
    refute_nil failed
    refute_nil success
    assert_operator failed, :<, success
  end


  def test_fleet_recovery_receipt_is_created_and_snapshot_precedes_service_stops
    assert_source SOURCE, "write_deploy_run_receipt() {"
    assert_source SOURCE, 'records_call write "$VPS_DEPLOY_RUN_ID" "$payload"'
    assert_source SOURCE, "export VPS_DEPLOY_LOCK_PID=${$}"
    assert_source SOURCE, "export VPS_DEPLOY_LOCK_IDENTITY=$identity"
    assert_source SOURCE, 'VPS_DEPLOY_RUN_ID="$(date -u'
    assert_source SOURCE, "VPS_DEPLOY_RECEIPT_SNAPSHOT_RECORDED=1"

    receipt_setup = SOURCE.index("# One durable receipt belongs to the lock-owning parent.")
    created = SOURCE.index('write_deploy_run_receipt || {', receipt_setup)
    snapshot = SOURCE.index("VPS_DEPLOY_RECEIPT_SNAPSHOT_RECORDED=1")
    first_stop = SOURCE.index('admin_service stop "$app"')
    refute_nil created
    refute_nil snapshot
    refute_nil first_stop
    assert_operator created, :<, snapshot
    assert_operator snapshot, :<, first_stop

    stage = SOURCE[/set_stage\(\) \{.*?^\}/m]
    refute_nil stage
    assert_includes stage, "write_deploy_run_receipt"
    assert_includes stage, "failed to persist recovery receipt"
  end

  # A child deploy inherits the run id, so its first receipt write happens at
  # `set_stage start`; records_call must already be defined by then.
  # A child deploy owns no lock and skips the pin block; it must still know
  # the pin its parent exported, or set -u kills it at host admission.
  def test_a_child_deploy_takes_its_pin_from_the_parent
    assert_source SOURCE, "pin=${VPS_DEPLOY_SHA:-}"
    assert_source SOURCE, "child deploy inherited no pinned SHA from its parent"
  end

  def test_records_call_is_defined_before_the_first_receipt_write
    assert_operator SOURCE.index("\nrecords_call() {"), :<, SOURCE.index("\nset_stage start")
  end

  def test_recovery_plan_is_explicit_and_never_deploys_or_checks_out_code
    recovery = SOURCE[/# Operator-driven recovery is intentionally separate from deploy\..*?(?=^# Pin the commit, prove it boots, record what is running\.)/m]
    refute_nil recovery
    assert_source SOURCE, "recover --plan"
    assert_source SOURCE, "recover --apply <run-id>"
    assert_includes recovery, "deploy-run-list"
    assert_includes recovery, "deploy-run-read"
    assert_includes recovery, "lock_process_identity"
    assert_source SOURCE, "other_deploy_processes() {"
    assert_source SOURCE, "pgrep -f 'OPENBSD/bin/vps-deploy'"
    scanner = SOURCE[/^other_deploy_processes\(\) \{.*?^\}/m]
    refute_nil scanner
    assert_includes scanner, "(( rc == 1 )) || return 1"
    assert_includes recovery, "cannot verify the process table"
    assert_includes recovery, "LIVE"
    assert_includes recovery, "AMBIGUOUS"
    assert_includes recovery, "RECOVERY AVAILABLE"
    assert_includes recovery, "restore_started"
    assert_includes recovery, 'admin_service check "$svc"'
    assert_includes recovery, 'wait_up "$port" "$restore_wait"'
    refute_includes recovery, "git_as_deploy_user fetch"
    refute_includes recovery, "git_as_deploy_user switch"
  end

  def test_recovery_invocation_uses_a_fresh_lock_and_historical_ports
    recovery = SOURCE[/# Operator-driven recovery is intentionally separate from deploy\..*?(?=^# Pin the commit, prove it boots, record what is running\.)/m]
    refute_nil recovery
    assert_source SOURCE, "unset VPS_DEPLOY_STARTED VPS_DEPLOY_LOCK_HELD"
    assert_source SOURCE, "VPS_DEPLOY_RESTORE_PORTS_FROM_RECEIPT=1"
    assert_source SOURCE, "ORDER) DEPLOY_ALL_DEGRADED=(${=one})"
    refute_source SOURCE, "ORDER) DEPLOY_ALL_DEGRADED=(${@=one})"
    assert_source SOURCE, "if [[ ${VPS_DEPLOY_RESTORE_PORTS_FROM_RECEIPT:-0} != 1 ]]; then"
    assert_source SOURCE, '[[ $owner_host == "$(hostname -s)" ]]'
    assert_includes recovery, "snapshot_recorded"
  end

  def test_recovery_requires_a_durable_service_snapshot_and_keeps_resource_guard_excluded
    recovery = SOURCE[/# Operator-driven recovery is intentionally separate from deploy\..*?(?=^# Pin the commit, prove it boots, record what is running\.)/m]
    refute_nil recovery
    assert_includes recovery, '[[ -n $VPS_DEPLOY_STARTED ]]'
    assert_includes recovery, "keep_deploy_flag"
    assert_source SOURCE, "VPS_DEPLOY_RESTORE_ATTEMPTED"
    assert_includes recovery, 'recovery_state: "pending"'
    assert_includes recovery, 'recovery_state: "complete"'
    assert_includes recovery, 'status: "recovered"'
  end


  # Retired bulk-sync and repository-scan doors are deleted, not stubbed: a
  # command that does not exist cannot run on vm23 or be revived by a typo fix.
  def test_retired_bulk_sync_and_scan_entrypoints_are_absent
    %w[vps_ci_all.sh vps_master_scan.sh].each do |name|
      refute File.exist?(File.join(ROOT, "OPENBSD", "bin", name)), "#{name} must stay deleted"
    end
  end

end
