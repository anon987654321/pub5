# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "fileutils"
require "tmpdir"

class VpsSafetyCheckTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  CHECK = File.join(ROOT, "checks", "vps_safety_check.rb")

  def run_check(root = nil)
    env = root ? { "VPS_SAFETY_ROOT" => root } : {}
    Open3.capture2e(env, RbConfig.ruby, CHECK)
  end

  # A copy of everything the check reads, so one file can be broken at a time.
  def with_fixture
    Dir.mktmpdir do |dir|
      openbsd = File.join(dir, "OPENBSD")
      mirror = File.join(openbsd, "mirror")
      FileUtils.mkdir_p(File.join(mirror, "etc"))
      FileUtils.cp_r(File.join(ROOT, "mirror", "etc", "rc.d"), File.join(mirror, "etc"))
      FileUtils.cp(File.join(ROOT, "mirror", "etc", "doas.conf"), File.join(mirror, "etc"))
      FileUtils.mkdir_p(File.join(mirror, "usr", "local", "libexec"))
      FileUtils.cp(File.join(ROOT, "mirror", "usr", "local", "libexec", "ci-prepare.ksh"),
                   File.join(mirror, "usr", "local", "libexec", "ci-prepare.ksh"))
      FileUtils.cp(File.join(ROOT, "mirror", "usr", "local", "libexec", "ci-run.ksh"),
                   File.join(mirror, "usr", "local", "libexec", "ci-run.ksh"))
      FileUtils.cp(File.join(ROOT, "mirror", "usr", "local", "libexec", "ci-sync.ksh"),
                   File.join(mirror, "usr", "local", "libexec", "ci-sync.ksh"))
      FileUtils.cp(File.join(ROOT, "mirror", "usr", "local", "libexec", "rails-task.ksh"),
                   File.join(mirror, "usr", "local", "libexec", "rails-task.ksh"))
      FileUtils.cp(File.join(ROOT, "mirror", "usr", "local", "libexec", "rails-sync.ksh"),
                   File.join(mirror, "usr", "local", "libexec", "rails-sync.ksh"))
      FileUtils.mkdir_p(File.join(mirror, "usr", "local", "bin"))
      FileUtils.cp(File.join(ROOT, "mirror", "usr", "local", "bin", "emergency_cpu.sh"),
                   File.join(mirror, "usr", "local", "bin", "emergency_cpu.sh"))
      FileUtils.cp(File.join(ROOT, "emergency_cpu.sh"), File.join(openbsd, "emergency_cpu.sh"))
      FileUtils.cp(File.join(ROOT, "mirror", "usr", "local", "bin", "resource_guard.sh"),
                   File.join(mirror, "usr", "local", "bin", "resource_guard.sh"))
      FileUtils.mkdir_p(File.join(openbsd, "bin"))
      FileUtils.mkdir_p(File.join(openbsd, "lib"))
      FileUtils.cp(File.join(ROOT, "lib", "deploy_records.rb"),
                   File.join(openbsd, "lib", "deploy_records.rb"))
      %w[
        vps_deploy_master.sh deploy-smoke.sh resource_guard.sh validate_doas.ksh
        vps_console.exp vps-deploy vps_install_all.sh
        vps-state restore_litestream.sh start_all_apps.sh
      ].each do |name|
        FileUtils.cp(File.join(ROOT, "bin", name), File.join(openbsd, "bin", name))
      end
      FileUtils.cp(File.join(ROOT, "BOOTSTRAP.sh"), File.join(openbsd, "BOOTSTRAP.sh"))
      FileUtils.cp(File.join(ROOT, "OPERATOR.sh"), File.join(openbsd, "OPERATOR.sh"))
      FileUtils.mkdir_p(File.join(dir, "RAILS", "mrdamascy"))
      %w[Gemfile Gemfile.lock falcon.rb preload.rb].each do |name|
        FileUtils.cp(File.join(ROOT, "..", "RAILS", "mrdamascy", name),
                     File.join(dir, "RAILS", "mrdamascy", name))
      end
      FileUtils.mkdir_p(File.join(dir, "RAILS"))
      FileUtils.cp(File.join(ROOT, "..", "RAILS", "_runtime_check.sh"),
                   File.join(dir, "RAILS", "_runtime_check.sh"))
      FileUtils.cp(File.join(ROOT, "..", "RAILS", "_bundle.sh"),
                   File.join(dir, "RAILS", "_bundle.sh"))
      %w[_service.sh _sync.sh _deploy.sh].each do |name|
        FileUtils.cp(File.join(ROOT, "..", "RAILS", name), File.join(dir, "RAILS", name))
      end
      %w[_core.sh _database.sh].each do |name|
        FileUtils.cp(File.join(ROOT, "..", "RAILS", name), File.join(dir, "RAILS", name))
      end
      FileUtils.mkdir_p(File.join(dir, "MASTER", "lib", "operator"))
      %w[services.rb status_report.rb].each do |name|
        FileUtils.cp(File.join(ROOT, "..", "MASTER", "lib", "operator", name),
                     File.join(dir, "MASTER", "lib", "operator", name))
      end
      yield dir, File.join(mirror, "etc", "doas.conf")
    end
  end

  def test_check_passes_on_the_tracked_tree
    out, status = run_check
    assert status.success?, "expected VPS safety check to pass, got:\n#{out}"
    assert_includes out, "VPS safety check passed"
  end

  def test_the_fixture_is_a_faithful_copy
    with_fixture do |dir, _|
      out, status = run_check(dir)
      assert status.success?, "an unmodified fixture must pass, or the must-flag tests below prove nothing:\n#{out}"
    end
  end

  def test_mrdamascy_production_service_must_use_falcon_host
    with_fixture do |dir, _|
      path = File.join(dir, "OPENBSD", "mirror", "etc", "rc.d", "mrdamascy")
      text = File.read(path).sub("falcon host", "falcon serve")
      File.write(path, text)
      out, status = run_check(dir)

      refute status.success?
      assert_includes out, "mrdamascy production service must use the Falcon host config"
    end
  end

  def test_mrdamascy_must_not_declare_puma_in_any_group
    with_fixture do |dir|
      path = File.join(dir, "RAILS", "mrdamascy", "Gemfile")
      File.write(path, File.read(path).sub("group :test do\n", "group :test do\n  gem \"puma\"\n"))
      out, status = run_check(dir)

      refute status.success?
      assert_includes out, "mrdamascy Gemfile must not declare Puma"
    end
  end

  def test_mrdamascy_secret_is_not_loaded_by_the_root_rc_script
    with_fixture do |dir, _|
      path = File.join(dir, "OPENBSD", "mirror", "etc", "rc.d", "mrdamascy")
      text = File.read(path).sub(
        '[[ -r /etc/mrdamascy.env ]] || { logger -t mrdamascy "missing /etc/mrdamascy.env"; exit 1; }',
        '[[ -r /etc/mrdamascy.env ]] && . /etc/mrdamascy.env'
      )
      File.write(path, text)
      out, status = run_check(dir)

      refute status.success?
      assert_includes out, "mrdamascy secret must be checked after dropping to the app user"
    end
  end

  def test_mrdamascy_secret_is_checked_inside_the_app_user_command
    with_fixture do |dir, _|
      path = File.join(dir, "OPENBSD", "mirror", "etc", "rc.d", "mrdamascy")
      text = File.read(path).sub("SECRET_KEY_BASE:?missing", "SECRET_KEY_BASE missing")
      File.write(path, text)
      out, status = run_check(dir)

      refute status.success?
      assert_includes out, "mrdamascy secret must be checked after dropping to the app user"
    end
  end

  def test_mrdamascy_falcon_host_must_bind_loopback_only
    with_fixture do |dir, _|
      path = File.join(dir, "RAILS", "mrdamascy", "falcon.rb")
      text = File.read(path).sub("http://127.0.0.1:", "http://0.0.0.0:")
      File.write(path, text)
      out, status = run_check(dir)

      refute status.success?
      assert_includes out, "mrdamascy Falcon host must use one Rack worker on loopback HTTP/1"
    end
  end

  def test_mrdamascy_rc_d_process_match_uses_the_live_endpoint
    with_fixture do |dir, _|
      path = File.join(dir, "OPENBSD", "mirror", "etc", "rc.d", "mrdamascy")
      text = File.read(path).sub('pexp=".*127\\\\.0\\\\.0\\\\.1:47314.*"',
                                'pexp=".*127\\\\.0\\\\.0\\\\.1:47315.*"')
      File.write(path, text)
      out, status = run_check(dir)

      refute status.success?
      assert_includes out, "mrdamascy rc.d process match must identify the Falcon loopback endpoint"
    end
  end

  def test_mrdamascy_rc_d_port_and_host_default_stay_aligned
    with_fixture do |dir, _|
      path = File.join(dir, "OPENBSD", "mirror", "etc", "rc.d", "mrdamascy")
      text = File.read(path).sub("PORT=47314", "PORT=47315")
      File.write(path, text)
      out, status = run_check(dir)

      refute status.success?
      assert_includes out, "mrdamascy rc.d service port must remain 47314"
    end
  end

  def test_mrdamascy_rc_d_stop_pattern_uses_the_live_endpoint
    with_fixture do |dir, _|
      path = File.join(dir, "OPENBSD", "mirror", "etc", "rc.d", "mrdamascy")
      text = File.read(path).sub('pkill -f "127\\\\.0\\\\.0\\\\.1:47314"',
                                'pkill -f "127\\\\.0\\\\.0\\\\.1:47315"')
      File.write(path, text)
      out, status = run_check(dir)

      refute status.success?
      assert_includes out, "mrdamascy rc.d stop pattern must target only the Falcon loopback endpoint"
    end
  end

  def test_mrdamascy_falcon_host_worker_count_is_fixed_to_one
    with_fixture do |dir, _|
      path = File.join(dir, "RAILS", "mrdamascy", "falcon.rb")
      text = File.read(path).sub("count 1", "count 2")
      File.write(path, text)
      out, status = run_check(dir)

      refute status.success?
      assert_includes out, "mrdamascy Falcon host must use one Rack worker on loopback HTTP/1"
    end
  end

  def test_mrdamascy_falcon_host_preserves_the_slow_boot_health_timeout
    with_fixture do |dir, _|
      path = File.join(dir, "RAILS", "mrdamascy", "falcon.rb")
      text = File.read(path).sub("health_check_timeout: 300", "health_check_timeout: 30")
      File.write(path, text)
      out, status = run_check(dir)

      refute status.success?
      assert_includes out, "mrdamascy Falcon host must use one Rack worker on loopback HTTP/1"
    end
  end

  def test_mrdamascy_falcon_preload_must_initialize_rails
    with_fixture do |dir, _|
      path = File.join(dir, "RAILS", "mrdamascy", "preload.rb")
      File.write(path, "# frozen_string_literal: true\\n")
      out, status = run_check(dir)

      refute status.success?
      assert_includes out, "mrdamascy Falcon preload must load the Rails environment"
    end
  end

  def test_bootstrap_checks_destinations_before_copying_privileged_trees
    with_fixture do |dir, _|
      path = File.join(dir, "OPENBSD", "BOOTSTRAP.sh")
      text = File.read(path)
      guard = text.index("Never copy privileged code through a symlinked system directory or file.")
      copy = text.index("for d in etc usr var; do")
      refute_nil guard
      refute_nil copy
      text[guard...copy] = ""
      File.write(path, text)
      out, status = run_check(dir)

      refute status.success?
      assert_includes out, "BOOTSTRAP.sh must preflight, install, and verify the root-owned load guard"
    end
  end

  def test_checkout_resource_guard_refuses_root_and_delegates_to_runner
    with_fixture do |dir, _|
      path = File.join(dir, "OPENBSD", "bin", "resource_guard.sh")
      text = File.read(path).sub('if [ "$(id -u)" -eq 0 ]; then', 'if [ "$(id -u)" -eq 1 ]; then')
      File.write(path, text)
      out, status = run_check(dir)

      refute status.success?
      assert_includes out, "checkout resource-guard entrypoint must refuse root and delegate to installed runner"
    end
  end

  def test_root_resource_guard_must_not_source_checkout_helper
    with_fixture do |dir, _|
      path = File.join(dir, "OPENBSD", "mirror", "usr", "local", "bin", "resource_guard.sh")
      text = File.read(path) + "\nGUARD_REPO=/home/dev/pub5\n"
      File.write(path, text)
      out, status = run_check(dir)

      refute status.success?
      assert_includes out, "root load guard must reject checkout helpers and never auto-restart core production services"
    end
  end
  def test_checkout_emergency_cpu_refuses_root_and_uses_installed_runner
    with_fixture do |dir, _|
      path = File.join(dir, "OPENBSD", "emergency_cpu.sh")
      text = File.read(path).sub('if [ "$(id -u)" -eq 0 ]; then', 'if [ "$(id -u)" -eq 1 ]; then')
      File.write(path, text)
      out, status = run_check(dir)

      refute status.success?
      assert_includes out, "checkout emergency CPU entrypoint must refuse root and delegate to installed runner"
    end
  end

  def test_emergency_cpu_runner_must_not_source_checkout_helper
    with_fixture do |dir, _|
      path = File.join(dir, "OPENBSD", "mirror", "usr", "local", "bin", "emergency_cpu.sh")
      text = File.read(path) + "\nGUARD_REPO=/home/dev/pub5\n"
      File.write(path, text)
      out, status = run_check(dir)

      refute status.success?
      assert_includes out, "emergency CPU runner must not source stale cleanup from checkout"
    end
  end

  def test_bootstrap_preflights_and_installs_emergency_cpu_runner
    with_fixture do |dir, _|
      path = File.join(dir, "OPENBSD", "BOOTSTRAP.sh")
      text = File.read(path).sub("usr/local/bin/emergency_cpu.sh", "usr/local/bin/removed-emergency.sh")
      File.write(path, text)
      out, status = run_check(dir)

      refute status.success?
      assert_includes out, "BOOTSTRAP.sh must preflight, install, and verify the root-owned emergency runner"
    end
  end

  def test_start_all_apps_must_use_native_rcctl
    with_fixture do |dir, _|
      path = File.join(dir, "OPENBSD", "bin", "start_all_apps.sh")
      text = File.read(path).sub('/usr/sbin/rcctl start', 'rcctl start')
      File.write(path, text)
      out, status = run_check(dir)

      refute status.success?
      assert_includes out, "start_all_apps must derive the app set and use native rcctl"
    end
  end

  def test_vps_state_service_reads_must_use_native_rcctl
    with_fixture do |dir, _|
      path = File.join(dir, "OPENBSD", "bin", "vps-state")
      text = File.read(path).sub('Open3.capture2e("doas", "-n", "/usr/sbin/rcctl", "check", service)',
                                 'Open3.capture2e("doas", "-n", "/usr/bin/true", "check", service)')
      File.write(path, text)
      out, status = run_check(dir)

      refute status.success?
      assert_includes out, "vps-state must read wheel-readable state and use native rcctl"
    end
  end

  def test_vps_state_fleet_recovery_must_read_the_durable_records
    with_fixture do |dir, _|
      path = File.join(dir, "OPENBSD", "bin", "vps-state")
      text = File.read(path).sub('directory = File.join(STAMP_DIR, "deploy_runs")',
                                 'directory = "/tmp/deploy_runs"')
      File.write(path, text)
      out, status = run_check(dir)

      refute status.success?
      assert_includes out, "vps-state must read wheel-readable state and use native rcctl"
    end
  end

  def test_litestream_recovery_must_use_native_rcctl
    with_fixture do |dir, _|
      path = File.join(dir, "OPENBSD", "bin", "restore_litestream.sh")
      text = File.read(path).sub('doas /usr/sbin/rcctl stop "$app"', 'doas rcctl stop "$app"')
      File.write(path, text)
      out, status = run_check(dir)

      refute status.success?
      assert_includes out, "Litestream recovery must use native rcctl"
    end
  end
  def test_deploy_smoke_service_checks_use_native_rcctl
    with_fixture do |dir, _|
      path = File.join(dir, "OPENBSD", "bin", "deploy-smoke.sh")
      text = File.read(path).sub('doas -n /usr/sbin/rcctl check "$svc"', 'doas rcctl check "$svc"')
      File.write(path, text)
      out, status = run_check(dir)

      refute status.success?
      assert_includes out, "deploy-smoke must use native rcctl"
    end
  end
  def test_vps_install_all_service_control_uses_native_rcctl
    with_fixture do |dir, _|
      path = File.join(dir, "OPENBSD", "bin", "vps_install_all.sh")
      text = File.read(path).sub('doas /usr/sbin/rcctl "$action" "$service"', 'doas rcctl "$action" "$service"')
      File.write(path, text)
      out, status = run_check(dir)

      refute status.success?
      assert_includes out, "fresh-box install must use native rcctl"
    end
  end
  def test_master_web_deploy_uses_native_filesystem_and_rcctl
    with_fixture do |dir, _|
      path = File.join(dir, "OPENBSD", "bin", "vps_deploy_master.sh")
      text = File.read(path).sub("doas /usr/sbin/rcctl restart master", "doas rcctl restart master")
      File.write(path, text)
      out, status = run_check(dir)

      refute status.success?
      assert_includes out, "MASTER web deploy must use native filesystem and rcctl operations"
    end
  end
  def test_vps_deploy_rejects_a_shadowed_terminal_handler
    with_fixture do |dir, _|
      path = File.join(dir, "OPENBSD", "bin", "vps-deploy")
      File.open(path, "a") { |file| file.write("\nfinish() { :; }\n") }
      out, status = run_check(dir)

      refute status.success?
      assert_includes out, "vps-deploy must define exactly one terminal finish handler and one EXIT trap"
    end
  end

  def test_vps_deploy_rejects_a_duplicate_terminal_exit_trap
    with_fixture do |dir, _|
      path = File.join(dir, "OPENBSD", "bin", "vps-deploy")
      File.open(path, "a") { |file| file.write("\ntrap finish EXIT\n") }
      out, status = run_check(dir)

      refute status.success?
      assert_includes out, "vps-deploy must define exactly one terminal finish handler and one EXIT trap"
    end
  end

  def test_vps_deploy_restores_services_before_releasing_guard_flag
    with_fixture do |dir, _|
      path = File.join(dir, "OPENBSD", "bin", "vps-deploy")
      original = File.read(path)
      restore_block = "  if (( rc != 0 )) && (( lock_owner )) && [[ \${VPS_DEPLOY_RESTORE_ATTEMPTED:-0} != 1 ]]; then\n" \
                      "    restore_started || {\n" \
                      "      restore_ok=0\n" \
                      "      print -u2 \"vps-deploy: production is NOT fully restored - see the lines above\"\n" \
                      "    }\n" \
                      "  fi\n"
      flag_lines = "  [[ -n $flag_keeper ]] && kill $flag_keeper 2>/dev/null\n" \
                   "  rm -f -- \"$deploy_flag\"\n"
      text = original.sub(restore_block, "")
      refute_equal original, text, "the safety mutation must match the current finish ordering"
      # Unsafe: the failure restore runs only after the guard flag is gone.
      text = text.sub(flag_lines, flag_lines + restore_block)
      File.write(path, text)
      out, status = run_check(dir)

      refute status.success?
      assert_includes out, "vps-deploy must keep the resource-guard flag active through failure restoration"
    end
  end

  def test_group_deploy_holds_resource_guard_exclusion_across_children
    with_fixture do |dir, _|
      path = File.join(dir, "OPENBSD", "bin", "vps-deploy")
      original = File.read(path)
      text = original.sub(
        "  # The parent spans child deploys and cooldowns. Its own flag keeps the\n" \
        "  # resource guard out until the whole batch (or its failure recovery) ends.\n" \
        "  keep_deploy_flag\n",
        ""
      )
      refute_equal original, text, "the safety mutation must remove the parent heartbeat"
      File.write(path, text)
      out, status = run_check(dir)

      refute status.success?
      assert_includes out, "vps-deploy group batches must hold a resource-guard exclusion across child deploys"
    end
  end

  def test_bootstrap_install_refuses_symlinked_system_destinations
    with_fixture do |dir, _|
      path = File.join(dir, "OPENBSD", "BOOTSTRAP.sh")
      text = File.read(path).sub("refusing symlinked privileged destination file",
                                 "symlinked target check weakened")
      File.write(path, text)
      out, status = run_check(dir)

      refute status.success?
      assert_includes out, "BOOTSTRAP.sh must preflight, install, and verify the root-owned load guard"
    end
  end

  def test_bootstrap_install_preflights_privileged_source_files
    with_fixture do |dir, _|
      path = File.join(dir, "OPENBSD", "BOOTSTRAP.sh")
      text = File.read(path).sub('installed resource guard is missing or symlinked',
                              'resource guard verification removed')
      File.write(path, text)
      out, status = run_check(dir)

      refute status.success?
      assert_includes out, "BOOTSTRAP.sh must preflight, install, and verify the root-owned load guard"
    end
  end
  def test_ci_prepare_path_validation_is_required
    with_fixture do |dir, _|
      path = File.join(dir, "OPENBSD", "mirror", "usr", "local", "libexec", "ci-prepare.ksh")
      File.write(path, File.read(path).sub('[ ! -L "$app_dir" ]', '[ -d "$app_dir" ]'))
      out, status = run_check(dir)

      refute status.success?
      assert_includes out, "ci-prepare must verify app paths and grant only checkout-read group access"
    end
  end

  def test_ci_runner_must_keep_its_timeout_bounded
    with_fixture do |dir, _|
      path = File.join(dir, "OPENBSD", "mirror", "usr", "local", "libexec", "ci-run.ksh")
      File.write(path, File.read(path).sub('[ "$timeout" -le 7200 ]', '[ "$timeout" -le 7201 ]'))
      out, status = run_check(dir)

      refute status.success?
      assert_includes out, "ci-run must retain bounded, sanitized execution as the app user"
    end
  end

  def test_keepenv_on_the_wheel_rule_is_refused
    with_fixture do |dir, doas|
      File.write(doas, File.read(doas).sub(/permit nopass setenv \{[^}]*\} :wheel as root/, "permit nopass keepenv :wheel as root"))
      out, status = run_check(dir)
      refute status.success?
      assert_includes out, "must not use keepenv"
    end
  end

  def test_every_allowlisted_variable_is_pinned
    with_fixture do |dir, doas|
      rules = File.read(doas).lines.map { |line| line.start_with?("permit") ? line.sub(" MAIL_IMG_FMT", "") : line }
      File.write(doas, rules.join)
      out, status = run_check(dir)
      refute status.success?
      assert_includes out, "setenv-allowlist MAIL_IMG_FMT"
    end
  end

  def test_fast_deploy_ack_is_allowlisted
    with_fixture do |dir, doas|
      text = File.read(doas).sub(" I_UNDERSTAND_FAST_DEPLOY RUN_PRODUCTION_SEEDS", " RUN_PRODUCTION_SEEDS")
      File.write(doas, text)
      out, status = run_check(dir)
      refute status.success?
      assert_includes out, "setenv-allowlist I_UNDERSTAND_FAST_DEPLOY"
    end
  end

  def test_master_scan_skip_requires_explicit_fast_deploy_ack
    with_fixture do |dir, _|
      path = File.join(dir, "OPENBSD", "BOOTSTRAP.sh")
      text = File.read(path).sub(
        '[[ ${SKIP_MASTER_SCAN} != 1 || ${I_UNDERSTAND_FAST_DEPLOY:-0} != 1 ]]',
        '[[ -n ${SKIP_MASTER_SCAN:-} ]]'
      )
      File.write(path, text)
      out, status = run_check(dir)
      refute status.success?
      assert_includes out, "MASTER scan bypass requires SKIP_MASTER_SCAN=1 plus I_UNDERSTAND_FAST_DEPLOY=1"
    end
  end

  # The ack is the whole safety of the console scripts, so hold the behaviour:
  # with it unset the script refuses before it spawns anything.
  def test_console_automation_refuses_without_the_ack
    expect = %w[/usr/bin/expect /usr/local/bin/expect].find { |path| File.executable?(path) }
    skip "expect not installed" unless expect

    env = { "I_UNDERSTAND_CONSOLE_RISK" => nil }
    out, status = Open3.capture2e(env, expect, "-f", File.join(ROOT, "bin", "vps_console.exp"), "short")
    assert_equal 1, status.exitstatus
    assert_includes out, "REFUSING"
  end

  # A second console script would reach vmctl without passing the ack.
  def test_a_second_console_script_is_refused
    with_fixture do |dir, _|
      File.write(File.join(dir, "OPENBSD", "bin", "vps_console_short.exp"), "#!/usr/bin/expect -f\nspawn ssh vm23\n")
      out, status = run_check(dir)
      refute status.success?
      assert_includes out, "vps_console_short.exp: console automation belongs in vps_console.exp"
    end
  end

  def test_console_scripts_live_in_openbsd_bin
    %w[validate_doas.ksh vps_console.exp].each do |name|
      assert File.file?(File.join(ROOT, "bin", name)), "missing #{name} in OPENBSD/bin"
    end
  end
  def test_resource_guard_retains_shed_state_when_start_fails
    with_fixture do |dir, _|
      path = File.join(dir, "OPENBSD", "mirror", "usr", "local", "bin", "resource_guard.sh")
      text = File.read(path).sub(
        /if rcctl start "\$svc" 2>\/dev\/null; then.*?^      fi/m,
        'rcctl start "$svc" 2>/dev/null || true
      restored=$svc'
      )
      File.write(path, text)
      out, status = run_check(dir)

      refute status.success?
      assert_includes out, "resource guard must retain shed ledger entries when service restore fails"
    end
  end

  def test_resource_guard_must_not_auto_restart_core_services
    with_fixture do |dir, _|
      path = File.join(dir, "OPENBSD", "mirror", "usr", "local", "bin", "resource_guard.sh")
      text = File.read(path).sub(
        'logger -t resource-guard "CRITICAL load=$load (threshold=$crit) - automatic core restart disabled; inspect processes and logs"',
        'logger -t resource-guard "critical"; ksh $EMERGENCY',
      )
      File.write(path, text)
      out, status = run_check(dir)

      refute status.success?
      assert_includes out, "never auto-restart core production services"
    end
  end

end
