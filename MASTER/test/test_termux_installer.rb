# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "tmpdir"

class TermuxInstallerTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  SCRIPT = File.join(ROOT, "tools", "device", "termux", "install.sh")
  MOBILE_INSTALLER = File.join(ROOT, "bin", "master-mobile-install")
  MASTER_ENTRYPOINT = File.join(ROOT, "bin", "master")

  def source = File.read(SCRIPT)
  def mobile_source = File.read(MOBILE_INSTALLER)
  def master_source = File.read(MASTER_ENTRYPOINT)

  def test_termux_bootstrap_delegates_to_canonical_ubuntu_installer
    assert_match(%r{#!/data/data/com\.termux/files/usr/bin/bash}, source)
    assert_includes source, "master-mobile-install"
    assert_includes source, "--ubuntu"
    refute_includes source, "ruby bin/deps install"
    refute_includes source, "exec ruby bin/master"
  end

  def test_termux_bootstrap_keeps_checkout_private_and_validates_origin
    assert_includes source, 'ROOT="${MASTER_INSTALL_DIR:-$HOME/pub5}"'
    assert_includes source, "remote get-url origin"
    assert_includes source, "canonical pub5"
    refute_match(%r{/storage/emulated/0|/sdcard}, source)
  end

  def test_bin_master_retains_the_ruby_entrypoint
    assert_match(%r{\A#!/usr/bin/env ruby\n}, master_source)
    assert_includes master_source, "master_proot_distro?"
  end

  def test_bin_master_refuses_non_ubuntu_proot_guests
    assert_includes master_source, 'ENV["container"] == "proot-distro"'
    assert_includes master_source, 'ENV["PD_CONTAINER"]'
    assert_includes master_source, 'master_proot_distro_id == "ubuntu"'
    assert_includes master_source, "exit 78"
  end

  def test_termux_host_automatically_enters_ubuntu_when_ruby_is_present
    assert_includes master_source, 'elsif master_termux_host?'
    assert_includes master_source, '"--ubuntu", "--launch", "--", *ARGV'
    assert_includes master_source, '"MASTER_INSTALL_DIR" => install_root'
  end

  def test_demo_is_portable_and_read_only
    assert_operator mobile_source.index("--demo"), :<, mobile_source.index("command -v pkg")
    assert_includes mobile_source, "no commands run, packages installed, files written, or Git state changed"
    assert_includes mobile_source, "device, guest and repository checks remain unmeasured"
  end

  def test_demo_runs_outside_termux_without_creating_files
    Dir.mktmpdir("mobile-install-demo") do |home|
      output, status = Open3.capture2e(
        { "HOME" => home, "MASTER_INSTALL_DIR" => File.join(home, "pub5"), "PREFIX" => "" },
        "sh", MOBILE_INSTALLER, "--demo"
      )

      assert status.success?, output
      assert_includes output, "plan 5/5"
      assert_includes output, "Ubuntu"
      assert_empty Dir.children(home)
    end
  end

  def test_demo_refuses_noncanonical_repository_without_mutating
    Dir.mktmpdir("mobile-install-demo-block") do |home|
      output, status = Open3.capture2e(
        { "HOME" => home, "MASTER_REPO_URL" => "https://example.invalid/pub5.git" },
        "sh", MOBILE_INSTALLER, "--demo"
      )

      refute status.success?
      assert_includes output, "would BLOCK: only the canonical HTTPS repository is allowed"
      assert_empty Dir.children(home)
    end
  end

  def test_demo_refuses_non_git_collision_without_mutating
    Dir.mktmpdir("mobile-install-demo-collision") do |home|
      target = File.join(home, "pub5")
      Dir.mkdir(target)
      output, status = Open3.capture2e(
        { "HOME" => home, "MASTER_INSTALL_DIR" => target },
        "sh", MOBILE_INSTALLER, "--demo"
      )

      refute status.success?
      assert_includes output, "would BLOCK: #{target} exists but is not a Git checkout"
      assert_empty Dir.children(target)
    end
  end

  def test_installer_defaults_to_ubuntu_and_proves_the_pinned_runtime
    assert_includes mobile_source, "proot-distro install ubuntu"
    assert_includes mobile_source, "ruby-build \"$ruby_version\" \"$ruby_home\""
    assert_includes mobile_source, 'grep -Fx "ubuntu $version" /etc/master-mobile-runtime'
    assert_includes mobile_source, "ruby bin/deps install"
    assert_includes mobile_source, "ruby bin/deps check"
    assert_includes mobile_source, "ruby bin/deps boot"
    assert_includes mobile_source, 'printf \'ubuntu %s\\n\' "$ruby_version" > /etc/master-mobile-runtime'
    refute_includes mobile_source, "proot-distro install debian"
    refute_includes mobile_source, "runtime=native"
  end

  def test_installer_default_launches_after_provisioning
    assert_includes mobile_source, "launch=1"
    assert_includes mobile_source, 'exec "$launcher" "$@"'
    assert_includes mobile_source, "--no-launch"
  end

  def test_launcher_reuses_ubuntu_and_forwards_arguments
    assert_includes mobile_source, 'proot-distro login --bind "$ROOT:/pub5" ubuntu'
    assert_includes mobile_source, 'exec bin/master "$@"'
  end

  def test_mobile_installer_shell_syntax
    output, status = Open3.capture2e("sh", "-n", MOBILE_INSTALLER)
    assert status.success?, output
  end

  def test_termux_bootstrap_shell_syntax
    skip "bash unavailable" unless system("command -v bash >/dev/null 2>&1")
    output, status = Open3.capture2e("bash", "-n", SCRIPT)
    assert status.success?, output
  end
end
