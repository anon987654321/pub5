#!/usr/bin/env ruby
# frozen_string_literal: true

# VPS_SAFETY_ROOT lets the test point this at a fixture tree holding the shapes
# it must flag; unset, it reads this checkout.
ROOT = ENV.fetch("VPS_SAFETY_ROOT", File.expand_path("../..", __dir__))
OPENBSD = File.join(ROOT, "OPENBSD")
TOOLING = File.join(ROOT, "OPENBSD", "bin")
failures = []

new_operator_path = File.join(OPENBSD, "OPERATOR.sh")
if File.file?(new_operator_path)
  new_operator = File.read(new_operator_path)
  %w[--plan --apply --verify].each do |mode|
    failures << "OPERATOR.sh must expose #{mode}" unless new_operator.include?(mode)
  end
  failures << "OPERATOR.sh must restrict installs to tracked mirror files" unless
    new_operator.include?('ls-files -z -- OPENBSD/mirror') && new_operator.include?('safe.directory=')
  failures << "OPERATOR.sh must map mirror paths directly to /" unless
    new_operator.include?('target=/$1') && new_operator.include?('MIRROR=')
  failures << "OPERATOR.sh must validate PF, relayd and httpd natively" unless
    new_operator.include?('pfctl -nf "$MIRROR/etc/pf.conf"') &&
    new_operator.include?('relayd -n -f "$MIRROR/etc/relayd.conf"') &&
    new_operator.include?('httpd -n -f "$MIRROR/etc/httpd.conf"')
  failures << "OPERATOR.sh must protect sshd_config and doas.conf" unless
    new_operator.include?('etc/ssh/sshd_config') && new_operator.include?('etc/doas.conf')
  failures << "OPERATOR.sh must not require Ruby for filesystem apply" if new_operator.match?(/(?:^|[\s;&|])(?:ruby|bundle)\s/)
else
  failures << "missing native OPENBSD/OPERATOR.sh"
end

doas_conf = File.join(OPENBSD, "mirror", "etc", "doas.conf")
if File.file?(doas_conf)
  text = File.read(doas_conf)
  failures << "doas.conf must end with newline (OpenBSD parser rejects EOF without one)" unless text.end_with?("\n")

  rules = text.lines.reject { |line| line.strip.empty? || line.strip.start_with?("#") }
  dev_rule = rules.find { |line| line.match?(/:wheel\s+as\s+root\b/) }

  # keepenv on the dev rule is a root RCE by construction: it carries RUBYOPT,
  # RUBYLIB, GEM_HOME and BUNDLE_* across the boundary, so `RUBYOPT=-r/tmp/x.rb doas
  # <anything>` runs as root with no shell involved. Removed 2026-08-02 for a measured
  # setenv allowlist; this is what stops it coming back with the next edit that finds
  # a variable missing. The root->root rule keeps keepenv on purpose — see the file.
  if dev_rule.nil?
    failures << "etc/doas.conf has no `:wheel as root` rule"
  else
    failures << "etc/doas.conf: wheel rule must not use keepenv (root RCE via RUBYOPT)" if dev_rule.include?("keepenv")
    # The whole measured allowlist (etc/doas.conf): each is read by a script run
    # under doas and assigned by none, so dropping one silently breaks that
    # script — --stage-1's DNS-wipe check, the console check, production seeds, the
    # deploy scan skip, the mail image format.
    allowlist = dev_rule[/setenv\s*\{([^}]*)\}/, 1].to_s.split
    %w[I_UNDERSTAND_DNS_WIPE I_UNDERSTAND_CONSOLE_RISK I_UNDERSTAND_FAST_DEPLOY RUN_PRODUCTION_SEEDS SKIP_MASTER_SCAN MAIL_IMG_FMT].each do |name|
      failures << "etc/doas.conf: wheel rule must setenv-allowlist #{name}" unless allowlist.include?(name)
    end
  end
else
  failures << "missing tracked etc/doas.conf"
end

operator_script = File.join(OPENBSD, "BOOTSTRAP.sh")

if File.file?(operator_script)
  operator = File.read(operator_script)
  unless operator.include?('[[ ${SKIP_MASTER_SCAN:-0} != 0 ]]') &&
         operator.include?('[[ ${SKIP_MASTER_SCAN} != 1 || ${I_UNDERSTAND_FAST_DEPLOY:-0} != 1 ]]')
    failures << "BOOTSTRAP.sh: MASTER scan bypass requires SKIP_MASTER_SCAN=1 plus I_UNDERSTAND_FAST_DEPLOY=1"
  end
else
  failures << "missing tracked BOOTSTRAP.sh"
end

guard_wrapper_path = File.join(OPENBSD, "bin", "resource_guard.sh")
guard_impl_path = File.join(OPENBSD, "mirror", "usr", "local", "bin", "resource_guard.sh")

if File.file?(guard_wrapper_path) && !File.symlink?(guard_wrapper_path) &&
   File.file?(guard_impl_path) && !File.symlink?(guard_impl_path)
  guard_wrapper = File.read(guard_wrapper_path)
  # Comments explain what was removed; only code can reintroduce it.
  guard_impl = File.readlines(guard_impl_path).grep_v(/^\s*#/).join
  guard_wrapper_contract = guard_wrapper.include?('if [ "$(id -u)" -eq 0 ]; then') &&
                          guard_wrapper.include?('runner=/usr/local/bin/resource_guard.sh') &&
                          guard_wrapper.include?('exec doas "$runner"') &&
                          !guard_wrapper.match?(/^\s*(?:rcctl|install|chmod|chown)\s/m)
  failures << "checkout resource-guard entrypoint must refuse root and delegate to installed runner" unless guard_wrapper_contract
  guard_impl_contract = guard_impl.include?('GUARD_HELPER=/usr/local/libexec/stale_ci_cleanup.ksh') &&
                        guard_impl.include?('[[ -f $GUARD_HELPER && ! -L $GUARD_HELPER ]]') &&
                        !guard_impl.include?("GUARD_REPO") &&
                        !guard_impl.include?("/home/dev/pub5/OPENBSD/mirror/usr/local/libexec/stale_ci_cleanup.ksh") &&
                        guard_impl.include?("automatic core restart disabled") &&
                        !guard_impl.include?("ksh $EMERGENCY")
  failures << "root load guard must reject checkout helpers and never auto-restart core production services" unless guard_impl_contract
  guard_restore_contract = guard_impl.match?(
    /if rcctl start "\$svc" 2>\/dev\/null; then\s+restored=\$svc\s+else\s+logger -t resource-guard "restore \$svc failed; retaining shed state for retry"\s+break\s+fi/m
  )
  failures << "resource guard must retain shed ledger entries when service restore fails" unless guard_restore_contract
  operator = File.read(File.join(OPENBSD, "BOOTSTRAP.sh"))
  source_list = operator[/typeset -a privileged_sources=\(.*?^  \)/m].to_s
  guard_install_contract = source_list.include?("usr/local/bin/resource_guard.sh") &&
                          operator.include?('install -o root -g wheel -m 555 "${src}/usr/local/bin/resource_guard.sh" /usr/local/bin/resource_guard.sh') &&
                          operator.include?('refusing symlinked privileged destination file: $rel') &&
                          operator.include?('installed resource guard is missing or symlinked')
  failures << "BOOTSTRAP.sh must preflight, install, and verify the root-owned load guard" unless guard_install_contract

  monitor_sources = %w[usr/local/bin/cpu-pressure-watch.sh usr/local/bin/network-watch.sh]
  monitor_contract = monitor_sources.all? { |path| source_list.include?(path) } &&
                     operator.include?("/usr/local/bin/cpu-pressure-watch.sh") &&
                     operator.include?("/usr/local/bin/network-watch.sh") &&
                     operator.include?('chown root:wheel "$f"') &&
                     operator.include?('chmod 555 "$f"')
  failures << "BOOTSTRAP.sh must install CPU and network monitor scripts as root-owned, read-only entrypoints" unless monitor_contract
else
  failures << "missing or symlinked resource-guard wrapper/runner source"
end

emergency_wrapper_path = File.join(OPENBSD, "emergency_cpu.sh")
emergency_impl_path = File.join(OPENBSD, "mirror", "usr", "local", "bin", "emergency_cpu.sh")

if File.file?(emergency_wrapper_path) && !File.symlink?(emergency_wrapper_path) &&
   File.file?(emergency_impl_path) && !File.symlink?(emergency_impl_path)
  emergency_wrapper = File.read(emergency_wrapper_path)
  emergency_impl = File.read(emergency_impl_path)
  wrapper_contract = emergency_wrapper.include?('if [ "$(id -u)" -eq 0 ]; then') &&
                     emergency_wrapper.include?('exec doas "$runner"') &&
                     emergency_wrapper.include?('runner=/usr/local/bin/emergency_cpu.sh') &&
                     !emergency_wrapper.include?("stale_ci_cleanup") &&
                     !emergency_wrapper.match?(/^\s*(?:rcctl|pkill)\b/m)
  failures << "checkout emergency CPU entrypoint must refuse root and delegate to installed runner" unless wrapper_contract
  runner_contract = emergency_impl.include?('GUARD_HELPER=/usr/local/libexec/stale_ci_cleanup.ksh') &&
                    emergency_impl.include?('[[ -f $GUARD_HELPER && ! -L $GUARD_HELPER ]]') &&
                    !emergency_impl.include?("GUARD_REPO") &&
                    !emergency_impl.include?("/home/dev/pub5/OPENBSD/mirror/usr/local/libexec/stale_ci_cleanup.ksh")
  failures << "emergency CPU runner must not source stale cleanup from checkout" unless runner_contract
  installer = File.read(File.join(OPENBSD, "BOOTSTRAP.sh"))
  source_list = installer[/typeset -a privileged_sources=\(.*?^  \)/m].to_s
  emergency_install_contract = source_list.include?("usr/local/bin/emergency_cpu.sh") &&
                               installer.include?("usr/local/bin/emergency_cpu.sh") &&
                              installer.include?('install -o root -g wheel -m 555 "${src}/usr/local/bin/emergency_cpu.sh" /usr/local/bin/emergency_cpu.sh') &&
                              installer.include?('refusing symlinked privileged destination file: $rel') &&
                              installer.include?('installed emergency CPU runner is missing or symlinked')
  failures << "BOOTSTRAP.sh must preflight, install, and verify the root-owned emergency runner" unless emergency_install_contract
else
  failures << "missing or symlinked emergency CPU wrapper/runner source"
end

validate_doas = File.join(TOOLING, "validate_doas.ksh")

if File.file?(validate_doas)
  # install_doas_conf_from_repo rolls /etc/doas.conf back when validation fails, so
  # validation has to test the thing that changed. `doas id` alone passes with a wrong
  # or empty allowlist — the rollback net covered lockout and not the actual risk.
  guard = File.read(validate_doas)
  unless guard.include?("validate_doas_passes_env")
    failures << "validate_doas.ksh must check that an allowlisted variable still crosses, " \
                "not only that dev can reach root"
  end
else
  failures << "missing OPENBSD/bin/validate_doas.ksh"
end

# Brokerless deployment contract. Ordinary host operations use OpenBSD's
# native rcctl/du/install/su commands. Rails tasks and tree sync remain fixed,
# app-user helpers; persistent deploy evidence is handled by a small data library.
admin_path = File.join(OPENBSD, "mirror", "usr", "local", "sbin", "pub5-admin")
admin_man = File.join(OPENBSD, "mirror", "usr", "local", "man", "man8", "pub5-admin.8")
failures << "pub5-admin must be removed from the tracked mirror" if File.exist?(admin_path) || File.symlink?(admin_path)
failures << "pub5-admin manual page must be removed" if File.exist?(admin_man) || File.symlink?(admin_man)

records_path = File.join(OPENBSD, "lib", "deploy_records.rb")
if File.file?(records_path) && !File.symlink?(records_path)
  records = File.read(records_path)
  records_contract = records.include?("class Records") &&
                     records.include?('File.join(@root, RUNS)') &&
                     records.include?("File::CREAT | File::EXCL") &&
                     records.include?("file.fsync") &&
                     records.include?("File.rename(temporary, target)") &&
                     records.include?("File.chown(0, wheel_gid, temporary)") &&
                     records.include?("File.chmod(0o640, temporary)") &&
                     records.include?("Inventory.new(root: repo_root)") &&
                     records.include?("terminal deploy-run receipt cannot be changed") &&
                     records.include?('deploy-run snapshot #{field} cannot change')
  failures << "deployment records must be inventory-derived, atomic and root:wheel readable" unless records_contract
else
  failures << "missing OPENBSD/lib/deploy_records.rb"
end

sync_path = File.join(OPENBSD, "mirror", "usr", "local", "libexec", "ci-sync.ksh")
if File.file?(sync_path) && !File.symlink?(sync_path)
  sync = File.read(sync_path)
  sync_contract = sync.include?("brgen|amber|bsdports|mrdamascy") &&
                  sync.include?('repo=/home/dev/pub5') &&
                  sync.include?('[ "$(id -un)" = "$app" ]') &&
                  sync.include?('tar xf - -C "$app_dir"') &&
                  sync.include?('sync_tree_stage') == false &&
                  sync.scan('git -c safe.directory="$repo" -C "$repo"').length >= 3 &&
                  !sync.match?(/^\s*(?:doas|sudo|chown)\b/)
  failures << "ci-sync helper must be fixed-path and app-owned, with no root mutation" unless sync_contract
else
  failures << "missing tracked usr/local/libexec/ci-sync.ksh"
end

prepare_path = File.join(OPENBSD, "mirror", "usr", "local", "libexec", "ci-prepare.ksh")
if File.file?(prepare_path) && !File.symlink?(prepare_path)
  prepare = File.read(prepare_path)
  prepare_contract = prepare.include?("brgen|amber|bsdports|mrdamascy") &&
                     prepare.include?('[ ! -L "$app_home" ]') &&
                     prepare.include?('[ ! -L "$app_dir" ]') &&
                     prepare.include?('[ "$(stat -f %u "$storage")" = "$app_uid" ]') &&
                     prepare.include?('storage="$app_dir/storage"') &&
                     prepare.include?('/usr/sbin/usermod -G _pub5ci "$app"')
  failures << "ci-prepare must verify app paths and grant only checkout-read group access" unless prepare_contract
else
  failures << "missing tracked usr/local/libexec/ci-prepare.ksh"
end

runner_path = File.join(OPENBSD, "mirror", "usr", "local", "libexec", "ci-run.ksh")
if File.file?(runner_path) && !File.symlink?(runner_path)
  runner = File.read(runner_path)
  runner_contract = runner.include?("brgen|amber|bsdports|mrdamascy") &&
                    runner.include?('[ "$timeout" -ge 1 ] && [ "$timeout" -le 7200 ]') &&
                    runner.include?('cd /home/$app/app') &&
                    runner.include?('exec /usr/bin/su -m "$app" -c "$script"') &&
                    runner.include?('/usr/local/bin/bundle') &&
                    runner.include?('unset RUBYOPT RUBYLIB RUBYPATH RUBYGEMS_GEMDEPS GEM_HOME GEM_PATH')
  failures << "ci-run must retain bounded, sanitized execution as the app user" unless runner_contract
else
  failures << "missing tracked usr/local/libexec/ci-run.ksh"
end

rails_task_path = File.join(OPENBSD, "mirror", "usr", "local", "libexec", "rails-task.ksh")
if File.file?(rails_task_path) && !File.symlink?(rails_task_path)
  rails_task = File.read(rails_task_path)
  rails_task_contract = rails_task.include?("master|brgen|amber|bsdports|mrdamascy") &&
                        rails_task.include?("overlay-initializers|overlay-public") &&
                        rails_task.include?("bundle-install|bundle-check|ci-bundle-install|db-prepare|db-seed|assets-precompile|ci") &&
                        rails_task.include?("db-storage-migrate") &&
                        rails_task.include?("secondary-db-check)") &&
                        rails_task.include?('exec /usr/bin/su -m "$app" -c "$script"') &&
                        rails_task.include?('unset BUNDLE_GEMFILE BUNDLE_PATH BUNDLE_BIN_PATH BUNDLE_WITH BUNDLE_WITHOUT') &&
                        !rails_task.include?("pub5-admin")
  failures << "Rails task helper must expose fixed task names and drop to the app user" unless rails_task_contract
else
  failures << "missing tracked usr/local/libexec/rails-task.ksh"
end

rails_sync_path = File.join(OPENBSD, "mirror", "usr", "local", "libexec", "rails-sync.ksh")
if File.file?(rails_sync_path) && !File.symlink?(rails_sync_path)
  rails_sync = File.read(rails_sync_path)
  rails_sync_contract = rails_sync.include?("app|shared") &&
                        rails_sync.include?("verticals") &&
                        rails_sync.include?('[ "$(id -un)" = "$app" ]') &&
                        rails_sync.include?('sync_tree_stage "$rails_root/$app" "$app_dir" yes') &&
                        rails_sync.include?('git -c safe.directory="$repo" -C "$repo" archive HEAD "RAILS/$source_rel"') &&
                        rails_sync.include?('archive_tracked_tree "$source_dir" "$stage"') &&
                        rails_sync.include?('for state in storage log; do') &&
                        rails_sync.include?('public/assets') &&
                        !rails_sync.match?(/^\s*(?:doas|sudo|chown)\b/)
  failures << "rails-sync must be app-owned, fixed-mode and preserve runtime state" unless rails_sync_contract
else
  failures << "missing tracked usr/local/libexec/rails-sync.ksh"
end

bootstrap = File.read(File.join(OPENBSD, "BOOTSTRAP.sh"))
bootstrap_contract = bootstrap.include?("typeset -a privileged_sources=(") &&
                     bootstrap.include?("usr/local/libexec/ci-prepare.ksh") &&
                     bootstrap.include?("usr/local/libexec/ci-run.ksh") &&
                     bootstrap.include?("usr/local/libexec/ci-sync.ksh") &&
                     bootstrap.include?("usr/local/libexec/rails-task.ksh") &&
                     bootstrap.include?("usr/local/libexec/rails-sync.ksh") &&
                     bootstrap.include?('[[ -L $f ]]') &&
                     !bootstrap.include?("pub5-admin")
failures << "BOOTSTRAP must install the app-user helpers without a command broker" unless bootstrap_contract

vps_deploy_path = File.join(OPENBSD, "bin", "vps-deploy")
deploy_source = File.read(vps_deploy_path)
deploy_contract = deploy_source.include?('"/usr/sbin/rcctl"') &&
                  deploy_source.include?('records_call write "$VPS_DEPLOY_RUN_ID" "$payload"') &&
                  deploy_source.include?('records_call write "$@"') &&
                  deploy_source.include?("Deploy::Records.new(repo_root: repo)") &&
                  deploy_source.include?("/usr/local/bin/resource_guard.sh") &&
                  deploy_source.include?("/usr/local/libexec/pub5/solid_queue_proof.rb") &&
                  !deploy_source.include?("pub5-admin") &&
                  !deploy_source.include?("PUB5_ADMIN")
failures << "vps-deploy must use native rcctl and direct durable records, not pub5-admin" unless deploy_contract

vps_state_path = File.join(OPENBSD, "bin", "vps-state")
vps_state = File.read(vps_state_path)
state_service = vps_state[/def service_state\(service\).*?^end/m]
state_contract = state_service &&
                 state_service.include?('"/usr/sbin/rcctl", "check", service') &&
                 !state_service.include?("pub5-admin") &&
                 vps_state.include?('File.join(STAMP_DIR, "deploy_runs")') &&
                 vps_state.include?("unsafe owner or mode") &&
                 vps_state.include?("Deploy::Inventory.new(root: ROOT)")
failures << "vps-state must read wheel-readable state and use native rcctl" unless state_contract

master_services = File.read(File.join(ROOT, "MASTER", "lib", "operator", "services.rb"))
master_status = File.read(File.join(ROOT, "MASTER", "lib", "operator", "status_report.rb"))
failures << "MASTER service controls must use native rcctl" unless
  master_services.include?('["doas", "-n", "/usr/sbin/rcctl", action.to_s, service]') &&
  !master_services.include?("pub5-admin")
failures << "MASTER service status must use native rcctl" unless
  master_status.include?('["doas", "-n", "/usr/sbin/rcctl", "check", service]') &&
  !master_status.include?("pub5-admin")

rails_core = File.read(File.join(ROOT, "RAILS", "_core.sh"))
rails_sync = File.read(File.join(ROOT, "RAILS", "_sync.sh"))
rails_runtime = File.read(File.join(ROOT, "RAILS", "_runtime_check.sh"))
rails_deploy = File.read(File.join(ROOT, "RAILS", "_deploy.sh"))
rails_database = File.read(File.join(ROOT, "RAILS", "_database.sh"))
rails_service = File.read(File.join(ROOT, "RAILS", "_service.sh"))
rails_bundle = File.read(File.join(ROOT, "RAILS", "_bundle.sh"))
failures << "RAILS service adapter must call rcctl directly" unless
  rails_core.include?('/usr/sbin/rcctl "$action" "$service"') && !rails_core.include?("pub5-admin")
failures << "RAILS deploy status must be atomic and wheel-readable" unless
  rails_core.include?('File.rename(temporary, target)') &&
  rails_core.include?('File.chmod(0o750, directory)') &&
  rails_core.include?('File.chmod(0o640, temporary)') &&
  !rails_core.include?("pub5-admin")
failures << "RAILS tree sync must su to the owning app and use the installed synchronizer" unless
  rails_sync.include?('/usr/local/libexec/rails-sync.ksh') &&
  rails_sync.include?('/usr/bin/su -m "$app_name"') && !rails_sync.include?("pub5-admin")
failures << "RAILS runtime tasks must invoke the fixed task helper directly" unless
  rails_runtime.include?('/usr/local/libexec/rails-task.ksh') && !rails_runtime.include?("pub5-admin")
failures << "RAILS deploy must prepare the app account without a command broker" unless
  rails_deploy.include?('/usr/sbin/useradd') &&
  rails_deploy.include?('/usr/local/libexec/ci-prepare.ksh') && !rails_deploy.include?("pub5-admin")
failures << "RAILS secrets must use atomic native file writes" unless
  rails_database.include?('File.link(temporary, target)') &&
  rails_database.include?("SECRET_KEY_BASE") && !rails_database.include?("pub5-admin")
failures << "RAILS service helper must use rcctl and read-only relay policy inspection" unless
  rails_service.include?('/usr/sbin/rcctl disable') &&
  rails_service.include?('File.lstat(path)') && !rails_service.include?("pub5-admin")
failures << "RAILS bundling must use app-owned caches rather than privileged CAS" unless
  !rails_bundle.include?("bundle_cas_") && !rails_bundle.include?("pub5-admin")

smoke_source = File.read(File.join(OPENBSD, "bin", "deploy-smoke.sh"))
failures << "deploy-smoke must use native rcctl" unless
  smoke_source.include?('doas -n /usr/sbin/rcctl check "$svc"') && !smoke_source.include?("pub5-admin")

install_all_source = File.read(File.join(OPENBSD, "bin", "vps_install_all.sh"))
failures << "fresh-box install must use native rcctl" unless
  install_all_source.include?('doas /usr/sbin/rcctl "$action" "$service"') && !install_all_source.include?("pub5-admin")

start_all_apps_path = File.join(OPENBSD, "bin", "start_all_apps.sh")
if File.file?(start_all_apps_path)
  start_all_apps = File.read(start_all_apps_path)
  start_all_contract = start_all_apps.include?("Deploy::Inventory.new(root: ARGV.fetch(0))") &&
                      start_all_apps.include?("/usr/sbin/rcctl enable") &&
                      start_all_apps.include?("/usr/sbin/rcctl start") &&
                      start_all_apps.include?('health_check.rb" --all-ready-apps') &&
                      !start_all_apps.include?("pub5-admin")
  failures << "start_all_apps must derive the app set and use native rcctl" unless start_all_contract
else
  failures << "missing OPENBSD/bin/start_all_apps.sh"
end

restore_litestream = File.read(File.join(OPENBSD, "bin", "restore_litestream.sh"))
failures << "Litestream recovery must use native rcctl" unless
  restore_litestream.include?('doas /usr/sbin/rcctl stop "$app"') &&
  restore_litestream.include?('doas /usr/sbin/rcctl start "$app"') &&
  restore_litestream.include?('doas /usr/sbin/rcctl check "$app"') &&
  !restore_litestream.include?("pub5-admin")

master_deploy = File.read(File.join(OPENBSD, "bin", "vps_deploy_master.sh"))
master_deploy_contract = master_deploy.include?("doas /usr/sbin/rcctl restart master") &&
                         master_deploy.include?("doas /bin/ksh -c") &&
                         master_deploy.include?("find \"$path\" -type l") &&
                         !master_deploy.include?("pub5-admin")
failures << "MASTER web deploy must use native filesystem and rcctl operations" unless master_deploy_contract

%w[ci-prepare.ksh ci-run.ksh ci-sync.ksh rails-task.ksh rails-sync.ksh].each do |name|
  path = File.join(OPENBSD, "mirror", "usr", "local", "libexec", name)
  failures << "usr/local/libexec/#{name} must not be a symlink" if File.symlink?(path)
end

finish_definition_count = deploy_source.scan(/^finish\(\) \{/).length
finish_exit_trap_count = deploy_source.scan(/^trap finish EXIT$/).length
failures << "vps-deploy must define exactly one terminal finish handler and one EXIT trap" unless
  finish_definition_count == 1 && finish_exit_trap_count == 1

deploy_finish = deploy_source[/^finish\(\) \{.*?^\}/m].to_s
restore_at = deploy_finish.index("restore_started")
keeper_stop_at = deploy_finish.index("kill $flag_keeper")
flag_remove_at = deploy_finish.index('rm -f -- "$deploy_flag"')
finish_guard_contract = restore_at && keeper_stop_at && flag_remove_at &&
                        restore_at < keeper_stop_at && restore_at < flag_remove_at
failures << "vps-deploy must keep the resource-guard flag active through failure restoration" unless finish_guard_contract

group_start = deploy_source.index('if [[ $deploy_target_kind == all || $deploy_target_kind == group ]]; then')
group_loop = group_start && deploy_source.index('  for one in $deploy_order; do', group_start)
group_guard_contract = group_start && group_loop &&
                       deploy_source[group_start...group_loop].include?("keep_deploy_flag")
failures << "vps-deploy group batches must hold a resource-guard exclusion across child deploys" unless group_guard_contract
console_main = File.join(TOOLING, "vps_console.exp")

if File.file?(console_main)
  text = File.read(console_main)
  unless text.include?("proc require_console_risk_ack") && text.match?(/^require_console_risk_ack$/)
    failures << "OPENBSD/bin/vps_console.exp must define and call require_console_risk_ack"
  end
  failures << "OPENBSD/bin/vps_console.exp must target vm23 only (found vm27)" if text.include?("vm27")
else
  failures << "missing OPENBSD/bin/vps_console.exp"
end

# vps_console.exp is the one console door, and the ack inside it is the whole
# safety. Any other expect script beside it is a way to the console that
# skipped that check, so it fails here rather than being trusted to delegate.
Dir.glob(File.join(TOOLING, "*.exp")).reject { |path| path == console_main }.each do |path|
  failures << "OPENBSD/bin/#{File.basename(path)}: console automation belongs in vps_console.exp as a mode"
end

Dir.glob(File.join(OPENBSD, "mirror", "etc", "rc.d", "*")).sort.each do |path|
  next unless File.file?(path)

  text = File.read(path)
  rel = path.delete_prefix("#{ROOT}/")
  if text.include?("falcon serve") && !text.match?(/\${_bundle} exec falcon/)
    failures << "#{rel} must invoke falcon via ${_bundle} exec (gem binstub, not PATH)"
  end
end

# The vm23 operator contract is Falcon-only. Mr Damascy had drifted to Puma;
# Capybara now serves its system tests with Falcon too, so Puma is in no group.
mrd_app = File.join(ROOT, "RAILS", "mrdamascy")
mrd_gemfile_path = File.join(mrd_app, "Gemfile")
mrd_lock_path = File.join(mrd_app, "Gemfile.lock")
mrd_falcon_config_path = File.join(mrd_app, "falcon.rb")
mrd_preload_path = File.join(mrd_app, "preload.rb")
mrd_service_path = File.join(OPENBSD, "mirror", "etc", "rc.d", "mrdamascy")
required_mrd_files = [mrd_gemfile_path, mrd_lock_path, mrd_falcon_config_path, mrd_preload_path, mrd_service_path]
if required_mrd_files.all? { |path| File.file?(path) && !File.symlink?(path) }
  mrd_gemfile = File.read(mrd_gemfile_path)
  mrd_lock = File.read(mrd_lock_path)
  mrd_falcon = File.read(mrd_falcon_config_path)
  mrd_preload = File.read(mrd_preload_path)
  mrd_service = File.read(mrd_service_path).lines.reject { |line| line.lstrip.start_with?("#") }.join
  runtime_gemfile = mrd_gemfile.split(/^group :(?:development|test)\b/).first.to_s
  lock_dependencies = mrd_lock[/^DEPENDENCIES\n(.*?)(?=^CHECKSUMS)/m, 1].to_s

  failures << "mrdamascy rc.d service port must remain 47314" unless mrd_service.match?(/^PORT=47314$/)
  failures << "mrdamascy Gemfile must declare Falcon as a runtime dependency" unless runtime_gemfile.match?(/^gem ["']falcon["']/)
  failures << "mrdamascy Gemfile must not declare Puma" if mrd_gemfile.match?(/^\s*gem ["']puma["']/)
  failures << "mrdamascy Gemfile.lock must lock Falcon and not Puma" unless
    lock_dependencies.lines.map(&:strip).include?("falcon") && !lock_dependencies.lines.map(&:strip).include?("puma")

  daemon_flags_line = mrd_service.lines.find { |line| line.start_with?("daemon_flags=") }.to_s
  root_setup = mrd_service.lines.take_while { |line| !line.start_with?("daemon_flags=") }.join
  secret_boundary = mrd_service.include?('[[ -r /etc/mrdamascy.env ]] ||') &&
                    !root_setup.include?(". /etc/mrdamascy.env") &&
                    mrd_service.include?('daemon_user="mrdamascy"') &&
                    daemon_flags_line.include?(". /etc/mrdamascy.env") &&
                    daemon_flags_line.include?("SECRET_KEY_BASE:?")
  failures << "mrdamascy secret must be checked after dropping to the app user" unless secret_boundary
  falcon_command = mrd_service[/^\s*_exec="([^"]+)"/, 1]
  expected_falcon_command = "exec ${_bundle} exec falcon host ${APP_DIR}/falcon.rb"
  failures << "mrdamascy production service must use the Falcon host config" unless
    falcon_command == expected_falcon_command
  falcon_pexp = mrd_service[/^\s*pexp="([^"]+)"/, 1]
  expected_pexp = %q{.*127\\\\.0\\\\.0\\\\.1:47314.*}
  failures << "mrdamascy rc.d process match must identify the Falcon loopback endpoint" unless
    falcon_pexp == expected_pexp
  falcon_stop_pattern = mrd_service[/^\s*pkill -f "([^"]+)"/, 1]
  expected_stop_pattern = %q{127\\\\.0\\\\.0\\\\.1:47314}
  failures << "mrdamascy rc.d stop pattern must target only the Falcon loopback endpoint" unless
    falcon_stop_pattern == expected_stop_pattern

  falcon_contract = mrd_falcon.include?('require "falcon/environment/rack"') &&
                    mrd_falcon.include?('service "mrdamascy" do') &&
                    mrd_falcon.include?("include Falcon::Environment::Rack") &&
                    mrd_falcon.match?(/^\s*count 1$/) &&
                    mrd_falcon.match?(/^\s*super\.merge\(health_check_timeout: 300\)$/) &&
                    mrd_falcon.include?("def container_options") &&
                    mrd_falcon.include?('port { ENV.fetch("PORT", 47314).to_i }') &&
                    mrd_falcon.include?('http://127.0.0.1:#{port}') &&
                    mrd_falcon.include?("Async::HTTP::Protocol::HTTP11")
  failures << "mrdamascy Falcon host must use one Rack worker on loopback HTTP/1" unless falcon_contract
  failures << "mrdamascy Falcon preload must load the Rails environment" unless
    mrd_preload.include?('require_relative "config/environment"')
else
  missing = required_mrd_files.reject { |path| File.file?(path) && !File.symlink?(path) }
  failures << "missing tracked Mr Damascy Falcon production files: #{missing.map { |path| path.delete_prefix(ROOT + File::SEPARATOR) }.join(", ")}"
end

if failures.any?
  warn "VPS safety check failures:"
  failures.each { |failure| warn "  - #{failure}" }
  exit 1
end

puts "VPS safety check passed (doas.conf, console guards, validate_doas.ksh, rc.d falcon)."
