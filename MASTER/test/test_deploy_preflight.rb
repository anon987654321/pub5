# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "fileutils"
require "yaml"
require_relative "../lib/operator/canary"

# The preflight refuses a commit that does not boot before anything on the box is
# stopped. These run it against a scratch tree and a stubbed runner; nothing here
# boots MASTER or touches vm23.
class DeployPreflightTest < Minitest::Test
  Pre = Operator::DeployPreflight

  def tree(files)
    dir = Dir.mktmpdir
    files.each do |path, body|
      FileUtils.mkdir_p(File.dirname(File.join(dir, path)))
      File.write(File.join(dir, path), body)
    end
    dir
  end

  def test_a_syntax_error_in_master_lib_fails_the_sweep_and_names_the_file
    dir = tree("MASTER/lib/voice/renderer/text_formatting.rb" => "def broken(\n", "MASTER/lib/ok.rb" => "x = 1\n")
    result = Pre.run(root: dir, runner: ->(*) { ["", true] })
    assert_equal ["syntax"], result.map(&:name), "the first failure stops the run"
    refute result.last.ok
    assert_includes result.last.detail, "MASTER/lib/voice/renderer/text_formatting.rb"
  ensure
    FileUtils.rm_rf(dir)
  end

  def test_rails_app_files_are_swept_too
    dir = tree("RAILS/brgen/app/models/x.rb" => "class X\n")
    refute Pre.syntax(dir).ok
  ensure
    FileUtils.rm_rf(dir)
  end

  def test_a_clean_tree_runs_all_four_checks_in_order_with_rehearse
    dir = tree("MASTER/lib/ok.rb" => "x = 1\n")
    calls = []
    result = Pre.run(root: dir, runner: ->(argv, chdir) { calls << [argv.last, chdir.delete_prefix(dir)]; ["", true] })
    assert_equal ["syntax", "law files", "boot smoke", "rehearse"], result.map(&:name)
    assert(result.all?(&:ok))
    assert_equal ["test/test_law_files_load.rb", "tools/boot_smoke.rb", "OPENBSD/bin/rehearse"], calls.map(&:first)
  ensure
    FileUtils.rm_rf(dir)
  end

  def test_the_box_variant_skips_rehearse
    dir = tree("MASTER/lib/ok.rb" => "x = 1\n")
    result = Pre.run(root: dir, rehearse: false, runner: ->(*) { ["", true] })
    assert_equal ["syntax", "law files", "boot smoke"], result.map(&:name)
  ensure
    FileUtils.rm_rf(dir)
  end

  def test_a_law_that_raises_at_boot_fails_the_law_check_by_name_and_is_reported_as_refusal
    dir = tree("MASTER/lib/ok.rb" => "x = 1\n")
    runner = lambda do |argv, _chdir|
      argv.last.end_with?("test_law_files_load.rb") ? ["BASELINE_COMPATIBILITY: missing bad, good\n", false] : ["", true]
    end
    result = Pre.run(root: dir, runner:)
    assert_equal "law files", result.last.name
    text = Pre.report(result)
    assert_includes text, "FAIL preflight law files"
    assert_includes text, "BASELINE_COMPATIBILITY: missing bad, good"
    assert_includes text, "law files FAILED"
    assert_includes text, "Nothing was stopped"
  ensure
    FileUtils.rm_rf(dir)
  end

  def test_a_rehearsal_failure_is_not_misreported_as_a_boot_failure
    result = [Pre::Result.new(name: "rehearse", ok: false, detail: "RAILS/test/test_path_idioms_test.rb failed")]

    report = Pre.report(result)

    assert_includes report, "deployment blocked during preflight"
    assert_includes report, "Nothing was stopped or pulled onto the box"
    refute_includes report, "this commit does not boot"
  end

  def test_failed_preflight_keeps_the_failing_test_name_before_later_green_checks
    failure = [
      "  1) Failure:",
      "RehearsalContractTest#test_missing_copy_path [OPENBSD/test/test_vps_deploy_contract.rb:42]:",
      "Expected: 1",
      "  Actual: 0",
      *Array.new(20) { |i| "ok  later check #{i}" },
    ].join("\n")

    result = Pre.shell(->(*) { [failure, false] }, ["ruby", "OPENBSD/bin/rehearse"], Master::REPO_ROOT)

    assert_includes result.detail, "RehearsalContractTest#test_missing_copy_path"
    assert_includes result.detail, "Actual: 0"
    assert_includes result.detail, "ok  later check 19"
  end

  def test_main_exits_one_on_failure_and_zero_on_a_clean_tree
    bad = tree("MASTER/lib/a.rb" => "def (\n")
    good = tree("MASTER/lib/a.rb" => "x = 1\n")
    assert_equal 1, Pre.main(["--root", bad, "--no-rehearse"], out: StringIO.new)
    assert_equal 0, Pre.syntax(good).ok ? 0 : 1
  ensure
    FileUtils.rm_rf([bad, good])
  end
  SHA = "a" * 40

  def fake_git(head: SHA, origin: SHA, dirty: "")
    lambda do |_root, *argv|
      case argv.first(2)
      when %w[rev-parse HEAD] then head
      when %w[rev-parse origin/main] then origin
      when %w[status --porcelain] then dirty
      else ""
      end
    end
  end

  FIXTURE_APPS = {
    "master" => { "title" => "MASTER", "domain" => "ai.example.test", "port" => 53_187,
                  "deploy_script" => "OPENBSD/master.sh", "deploy_root" => "MASTER/web",
                  "public" => true, "deploy_order" => 10 },

    "brgen" => { "title" => "Brgen", "domain" => "brgen.example.test", "port" => 38_182,
                 "deploy_script" => "RAILS/brgen/deploy.sh", "deploy_root" => "RAILS/brgen",
                 "public" => true, "deploy_order" => 20 },

    "amber" => { "title" => "Amber", "domain" => "amber.example.test", "port" => 61_352,
                 "deploy_script" => "RAILS/amber/deploy.sh", "deploy_root" => "RAILS/amber",
                 "public" => true, "deploy_order" => 30 },

    "bsdports" => { "title" => "BSDPorts", "domain" => "bsdports.example.test", "port" => 47_312,
                    "deploy_script" => "RAILS/bsdports/deploy.sh", "deploy_root" => "RAILS/bsdports",
                    "public" => true, "deploy_order" => 40 },

    "future_service" => { "title" => "Future Service", "domain" => "future.example.test", "port" => 47_313,
                          "deploy_script" => "RAILS/future_service/deploy.sh",
                          "deploy_root" => "RAILS/future_service", "public" => true, "deploy_order" => 50 },
  }.freeze

  def remote(env: {}, runner: ->(*) { ["", true] }, app: "all",
             ci_runner: ->(**) { true }, admission_check: ->(**) { [true, nil] },
             connection_check: nil, git: nil, **git_state)
    dir = Dir.mktmpdir
    FileUtils.mkdir_p(File.join(dir, "MASTER", "lib"))
    FileUtils.mkdir_p(File.join(dir, "RAILS"))
    File.write(File.join(dir, "MASTER", "lib", "ok.rb"), "x = 1\n")
    File.write(File.join(dir, "RAILS", "apps.yml"), YAML.dump("apps" => FIXTURE_APPS))
    with_fixture_ci_receipts(dir) do
      Pre.remote_command(root: dir, app:, env:, git: git || fake_git(**git_state), runner:, out: StringIO.new,
                         ci_runner:, admission_check:, connection_check:)
    end
  ensure
    FileUtils.rm_rf(dir)
  end

  # The fixture is no git checkout, and a recorded pass must not reach the
  # operator's real ~/.pub5/ci: key the receipt by hand, keep it in the fixture.
  def with_fixture_ci_receipts(dir, &block)
    receipts = ENV.fetch("PUB5_CI_RECEIPT_DIR", nil)
    ENV["PUB5_CI_RECEIPT_DIR"] = File.join(dir, "ci")
    Operator::CiReceipt.stub(:key, ->(app:, **) { "fixture-#{app}" }) do
      Pre.stub(:ruby_version, "test", &block)
    end
  ensure
    ENV["PUB5_CI_RECEIPT_DIR"] = receipts
  end

  def test_git_out_rejects_a_nonzero_exit_instead_of_treating_empty_output_as_clean
    status = Object.new
    status.define_singleton_method(:success?) { false }
    status.define_singleton_method(:exitstatus) { 128 }

    Master::Io::Exec.stub(:capture2, ->(*args, **options) { ["", status] }) do
      error = assert_raises(Pre::GitCommandError) { Pre.git_out("/tmp/pub5", "fetch", "origin", "main") }
      assert_includes error.message, "git fetch origin main failed (128)"
    end
  end

  def test_git_out_reports_a_missing_git_executable_as_a_repository_error
    Master::Io::Exec.stub(:capture2, ->(*args, **options) { raise Errno::ENOENT, "git" }) do
      error = assert_raises(Pre::GitCommandError) { Pre.git_out("/tmp/pub5", "fetch", "origin", "main") }
      assert_match(/git fetch origin main could not run \(Errno::ENOENT:/, error.message)
    end
  end

  def test_remote_command_blocks_when_git_fetch_fails_before_running_preflight
    calls = []
    git = lambda do |_root, *argv|
      calls << argv
      raise Pre::GitCommandError, "git fetch origin main failed (128)"
    end

    ok, reason = remote(git:, runner: ->(*) { flunk "preflight must not run after a failed fetch" })

    refute ok
    assert_includes reason, "repository preflight failed"
    assert_includes reason, "nothing was sent to vm23"
    assert_equal [["fetch", "-q", "origin", "main"]], calls
  end

  def test_remote_command_blocks_when_git_status_cannot_prove_a_clean_tree
    base = fake_git
    git = lambda do |root, *argv|
      raise Pre::GitCommandError, "git status --porcelain failed (128)" if argv.first(2) == %w[status --porcelain]

      base.call(root, *argv)
    end

    ok, reason = remote(git:, runner: ->(*) { flunk "preflight must not run when git status is unknown" })

    refute ok
    assert_includes reason, "git status --porcelain failed"
    assert_includes reason, "nothing was sent to vm23"
  end

  # Every selected Rails suite runs on the workstation before SSH begins.
  def test_a_green_local_ci_attests_that_exact_commit_for_one_app
    ran = []
    ok, command = remote(app: "brgen", ci_runner: ->(root:, app:) { ran << app; true })

    assert ok
    assert_equal ["brgen"], ran
    assert_equal "cd /home/dev/pub5 && VPS_DEPLOY_SHA=#{SHA} VPS_DEPLOY_PREFLIGHT_SHA=#{SHA} " \
                 "VPS_DEPLOY_CI_SHA=#{SHA} zsh OPENBSD/bin/vps-deploy brgen", command
  end

  def test_local_ci_uses_the_bounded_executor_and_clears_foreign_bundle_state
    dir = tree("RAILS/brgen/bin/ci" => "#!/bin/sh\nexit 0\n")
    ENV["BUNDLER_ORIG_GEM_HOME"] = "/master/gems"
    captured = {}
    status = Object.new
    status.define_singleton_method(:success?) { true }
    runner = lambda do |*argv, **options|
      captured[:argv] = argv
      captured[:options] = options
      ["ci output\n", status]
    end
    output = StringIO.new

    Operator::RubyRunner.stub(:ruby_cmd, "/opt/ruby/bin/ruby") do
      Operator::RubyRunner.stub(:bundle_cmd, "/opt/bundle/bin/bundle") do
        Master::Io::Exec.stub(:capture2e, runner) do
          assert Pre.local_ci(root: dir, app: "brgen", out: output, err: StringIO.new)
        end
      end
    end

    env, ruby, script = captured.fetch(:argv)
    assert_equal "/opt/ruby/bin/ruby", ruby
    assert_equal "bin/ci", script
    assert_equal %w[/opt/ruby/bin /opt/bundle/bin], env.fetch("PATH").split(":").first(2)
    assert_includes env.fetch("PATH").split(":"), File.join(Gem.user_dir, "bin")
    assert_nil env.fetch("BUNDLE_GEMFILE")
    assert_nil env.fetch("BUNDLE_LOCKFILE")
    Pre::FOREIGN_BUNDLE_ENV.each { |key| assert_nil env.fetch(key), key }
    assert_nil env.fetch("BUNDLER_ORIG_GEM_HOME")
    assert_equal "brgen", env.fetch("PUB5_CI_APP")
    assert_equal File.join(dir, "RAILS", "brgen"), captured.fetch(:options).fetch(:chdir)
    assert_equal Pre::LOCAL_CI_TIMEOUT, captured.fetch(:options).fetch(:timeout)
    assert_equal true, captured.fetch(:options).fetch(:raise_on_timeout)
    assert_equal "ci output\n", output.string
  ensure
    ENV.delete("BUNDLER_ORIG_GEM_HOME")
    FileUtils.rm_rf(dir)
  end

  def test_local_ci_timeout_is_reported_and_returns_failure
    dir = tree("RAILS/brgen/bin/ci" => "#!/bin/sh\nexit 0\n")
    output = StringIO.new
    errors = StringIO.new
    timeout = Master::Io::Exec::TimeoutError.new("timed out", result: ["partial ci output\n", nil])

    Operator::RubyRunner.stub(:ruby_cmd, "/opt/ruby/bin/ruby") do
      Operator::RubyRunner.stub(:bundle_cmd, "/opt/ruby/bin/bundle") do
        Master::Io::Exec.stub(:capture2e, lambda { |*args, **kwargs| raise timeout }) do
          refute Pre.local_ci(root: dir, app: "brgen", out: output, err: errors)
        end
      end
    end

    assert_includes output.string, "partial ci output"
    assert_includes errors.string, "timed out after #{Pre::LOCAL_CI_TIMEOUT}s"
  ensure
    FileUtils.rm_rf(dir)
  end

  def test_a_red_local_ci_sends_nothing
    ok, reason = remote(app: "amber", ci_runner: ->(**) { false })

    refute ok
    assert_includes reason, "amber bin/ci failed here"
    assert_includes reason, "nothing was sent to the box"
  end

  def test_local_ci_cannot_be_delegated_to_vm23
    ran = []
    ok, command = remote(app: "bsdports", env: { "VPS_DEPLOY_LOCAL_CI" => "0" },
                         ci_runner: ->(root:, app:) { ran << app; true })

    assert ok
    assert_equal ["bsdports"], ran
    assert_includes command, "VPS_DEPLOY_CI_SHA=#{SHA}"
  end

  def test_new_inventory_app_gets_local_ci_without_a_code_list_change
    ran = []
    ok, command = remote(app: "future_service", ci_runner: ->(root:, app:) { ran << app; true })

    assert ok
    assert_equal ["future_service"], ran
    assert_includes command, "VPS_DEPLOY_CI_SHA=#{SHA}"
  end

  def test_rails_group_runs_every_selected_ci_serially_on_the_workstation
    ran = []
    ok, command = remote(app: "rails", ci_runner: ->(root:, app:) { ran << app; true })

    assert ok
    assert_equal %w[brgen amber bsdports future_service], ran
    assert_includes command, "VPS_DEPLOY_CI_SHA=#{SHA}"
    assert_includes command, "vps-deploy rails"
  end

  def test_all_target_runs_each_rails_ci_locally_before_returning_a_command
    ran = []
    ok, command = remote(app: "all", ci_runner: ->(root:, app:) { ran << app; true })

    assert ok
    assert_equal %w[brgen amber bsdports future_service], ran
    assert_includes command, "VPS_DEPLOY_CI_SHA=#{SHA}"
  end

  def test_workstation_deploy_uses_the_operator_without_a_redeploy_wrapper
    source = File.read(File.expand_path("../bin/operator", __dir__))

    refute File.exist?(File.expand_path("../bin/redeploy", __dir__))
    assert_includes source, "bin/operator vps deploy <app|group|all> [--remote]"
    assert_includes source, "Operator::DeployPreflight.remote_command"
  end

  def test_full_release_fails_fast_when_openbsd_receipt_is_missing
    dir = tree("MASTER/lib/a.rb" => "x = 1\n")

    ok, reason = Pre.openbsd_release_admission(root: dir)

    refute ok
    assert_includes reason, "MASTER/.master/openbsd_preflight.json"
    assert_includes reason, "run /fix OPENBSD before the full release"
  ensure
    FileUtils.rm_rf(dir) if dir
  end

  def test_vm23_identity_requires_the_exact_receipt_hostname_release_and_architecture
    dir = tree(
      "OPENBSD/data/operator.yml" => "meta:\n  vps: dev@brgen.no\nhost_scope:\n  canonical_hosts: [vm23]\n"
    )
    expected = { "hostname" => "vm23", "os_release" => "7.8", "architecture" => "amd64" }
    asked = []
    probe = lambda do |command|
      asked << command
      {
        "hostname" => ["vm23\n", true],
        "uname -srm" => ["OpenBSD 7.8 amd64\n", true]
      }.fetch(command)
    end

    ok, reason = Pre.verify_vm23_identity(root: dir, expected:, probe:)

    assert ok, reason
    assert_equal ["hostname", "uname -srm"], asked
  ensure
    FileUtils.rm_rf(dir)
  end

  # The live host answered `hostname` with its FQDN (2026-11-24); a receipt for
  # the canonical vm23 refused every release until the alias table covered it.
  def test_vm23_identity_accepts_the_hosts_own_fqdn
    dir = tree(
      "OPENBSD/data/operator.yml" => "meta:\n  vps: dev@brgen.no\nhost_scope:\n  canonical_hosts: [vm23]\n"
    )
    expected = { "hostname" => "vm23", "os_release" => "7.8", "architecture" => "amd64" }
    answers = { "hostname" => ["brgen.openbsd.amsterdam\n", true], "uname -srm" => ["OpenBSD 7.8 amd64\n", true] }

    ok, reason = Pre.verify_vm23_identity(root: dir, expected:, probe: ->(command) { answers.fetch(command) })

    assert ok, reason
  ensure
    FileUtils.rm_rf(dir)
  end

  def test_vm23_identity_rejects_the_hypervisor_or_any_other_host
    dir = tree(
      "OPENBSD/data/operator.yml" => "meta:\n  vps: dev@brgen.no\nhost_scope:\n  canonical_hosts: [vm23]\n"
    )
    expected = { "hostname" => "vm23", "os_release" => "7.8", "architecture" => "amd64" }

    ok, reason = Pre.verify_vm23_identity(
      root: dir, expected:, probe: ->(command) { command == "hostname" ? ["server4\n", true] : flunk("OS probe must not follow a host mismatch") }
    )

    refute ok
    assert_includes reason, "admitted production host is vm23"
    assert_includes reason, "nothing was deployed"
  ensure
    FileUtils.rm_rf(dir)
  end

  def test_vm23_identity_rejects_a_release_or_architecture_mismatch
    dir = tree(
      "OPENBSD/data/operator.yml" => "meta:\n  vps: dev@brgen.no\nhost_scope:\n  canonical_hosts: [vm23]\n"
    )
    expected = { "hostname" => "vm23", "os_release" => "7.8", "architecture" => "amd64" }
    probe = ->(command) { command == "hostname" ? ["vm23\n", true] : ["OpenBSD 7.9 arm64\n", true] }

    ok, reason = Pre.verify_vm23_identity(root: dir, expected:, probe:)

    refute ok
    assert_includes reason, "OS identity mismatch"
    assert_includes reason, "nothing was deployed"
  ensure
    FileUtils.rm_rf(dir)
  end

  def test_ssh_connection_failure_blocks_before_boot_preflight_and_rails_ci
    ok, reason = remote(
      connection_check: ->(**) { [false, "SSH to vm23 failed: key unavailable"] },
      runner: ->(*) { flunk "local preflight must not run without verified SSH access" },
      ci_runner: ->(**) { flunk "Rails CI must not run without verified SSH access" }
    )

    refute ok
    assert_equal "SSH to vm23 failed: key unavailable", reason
  end

  def test_remote_command_pins_the_sha_and_attests_preflight_and_all_rails_ci
    ok, command = remote
    assert ok
    assert_equal "cd /home/dev/pub5 && VPS_DEPLOY_SHA=#{SHA} VPS_DEPLOY_PREFLIGHT_SHA=#{SHA} VPS_DEPLOY_CI_SHA=#{SHA} zsh OPENBSD/bin/vps-deploy all", command
  end

  def test_remote_command_refuses_a_failed_preflight_and_sends_nothing
    ok, reason = remote(runner: ->(argv, _c) { [argv.last.end_with?("boot_smoke.rb") ? "boom" : "", !argv.last.end_with?("boot_smoke.rb")] })
    refute ok
    assert_includes reason, "preflight failed"
    assert_includes reason, "nothing was sent to the box"
  end

  def test_remote_command_refuses_a_head_that_is_not_origin_main
    ok, reason = remote(origin: "b" * 40)
    refute ok
    assert_includes reason, "is not origin/main"
  end

  def test_remote_command_refuses_a_dirty_tree_because_it_would_judge_the_edits
    ok, reason = remote(dirty: " M MASTER/lib/x.rb\n")
    refute ok
    assert_includes reason, "commit these first"
  end

  def test_remote_command_refuses_untracked_governed_source
    ok, reason = remote(dirty: "?? RAILS/brgen/config/boot.rb\n")

    refute ok
    assert_includes reason, "commit these first"
    assert_includes reason, "untracked files"
    assert_includes reason, "RAILS/brgen/config/boot.rb"
  end


  def test_remote_command_refuses_untracked_studio_source
    ok, reason = remote(dirty: "?? STUDIO/dilla/new_take.rb\n")

    refute ok
    assert_includes reason, "commit these first"
    assert_includes reason, "STUDIO/dilla/new_take.rb"
  end

  def test_remote_full_release_checks_openbsd_admission_before_long_preflight
    ok, reason = remote(
      admission_check: ->(**) { [false, "RTFM_FIRST receipt missing"] },
      runner: ->(*) { flunk "local preflight must not run before OpenBSD admission" },
      ci_runner: ->(**) { flunk "Rails CI must not run before OpenBSD admission" }
    )

    refute ok
    assert_equal "RTFM_FIRST receipt missing", reason
  end

  # STUDIO runs nothing on vm23; its suite is its own proof, not a release
  # gate (operator decision 2026-11-24). Uncommitted STUDIO edits are still
  # refused: test_remote_command_refuses_untracked_studio_source.
  def test_full_release_does_not_gate_on_the_studio_suite
    calls = []
    runner = lambda do |argv, chdir|
      calls << [argv, chdir]
      ["", true]
    end

    ok, command = remote(runner:)

    assert ok
    assert_includes command, "VPS_DEPLOY_SHA=#{SHA}"
    studio_calls = calls.select { |_argv, chdir| File.basename(chdir) == "STUDIO" }
    assert_empty studio_calls, "STUDIO's suite must not gate a vm23 release"
  end

  def test_remote_break_glass_needs_the_acknowledgement
    ok, reason = remote(env: { "VPS_DEPLOY_SKIP_PREFLIGHT" => "1" }, runner: ->(*) { flunk "the preflight must not run" })
    refute ok
    assert_includes reason, "I_UNDERSTAND_FAST_DEPLOY=1"

    ran = []
    ok, command = remote(env: { "VPS_DEPLOY_SKIP_PREFLIGHT" => "1", "I_UNDERSTAND_FAST_DEPLOY" => "1" },
                         runner: ->(*) { flunk "preflight skipped" },
                         ci_runner: ->(root:, app:) { ran << app; true })
    assert ok
    assert_equal %w[brgen amber bsdports future_service], ran
    assert_includes command, "VPS_DEPLOY_SHA=#{SHA}"
    assert_includes command, "VPS_DEPLOY_SKIP_PREFLIGHT=1"
    assert_includes command, "VPS_DEPLOY_CI_SHA=#{SHA}"
    refute_includes command, "VPS_DEPLOY_PREFLIGHT_SHA"
  end

  def test_the_operator_surface_goes_through_the_preflight_for_remote_deploys
    source = File.read(File.expand_path("../bin/operator", __dir__))
    deploy = source[/when "deploy"\n.*?when "admin"/m]
    assert_includes deploy, "Operator::DeployPreflight.remote_command"
    receipt = deploy.index("ensure_openbsd_receipt(app)")
    admission = deploy.index("Operator::DeployPreflight.remote_command")
    launch = deploy.index("remote_deploy_launch_command(")
    refute_nil receipt
    assert_operator receipt, :<, admission
    assert_operator admission, :<, launch
  end

  # A finished, uncollected pane blocked new launches for the 24 h hold. It is
  # saved locally and closed after admission; a pane with no exit marker is a
  # running deploy and is never killed.
  def test_a_finished_held_pane_is_saved_and_closed_before_the_next_launch
    source = File.read(File.expand_path("../bin/operator", __dir__))
    deploy = source[/when "deploy"\n.*?when "admin"/m]
    recover = deploy.index("recover_finished_deploy_pane(session)")
    refute_nil recover
    assert_operator deploy.index("Operator::DeployPreflight.remote_command"), :<, recover
    assert_operator recover, :<, deploy.index("remote_deploy_launch_command(")

    helper = source[/def recover_finished_deploy_pane\(session\).*?^end/m]
    marker = helper.index("PUB5_DEPLOY_EXIT=")
    unless_running = helper.index("unless exit_code")
    kill = helper.index("kill-session")
    assert marker && unless_running && kill
    assert_operator unless_running, :<, kill
    assert_includes helper, "File::EXCL, 0o600"
  end

  def test_remote_deploy_refuses_to_run_inline_when_tmux_is_missing
    source = File.read(File.expand_path("../bin/operator", __dir__))
    remote = source[/remote_script = <<~ZSH.*?^  ZSH$/m]
    refute_nil remote
    assert_includes remote, "tmux is required; nothing was started"
    assert_includes remote, "exit 69"
    refute_includes remote, '#{command}'
  end

end
