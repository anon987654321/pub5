# frozen_string_literal: true

require "minitest/autorun"
require "open3"

class TermuxInstallerTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  SCRIPT = File.join(ROOT, "tools", "device", "termux", "install.sh")
  MOBILE_INSTALLER = File.join(ROOT, "bin", "master-mobile-install")

  def source = File.read(SCRIPT)
  def mobile_source = File.read(MOBILE_INSTALLER)

  def test_installer_rejects_non_termux_shells
    assert_match(%r{#!/data/data/com\.termux/files/usr/bin/bash}, source)
    assert_match(/Run this inside Termux/, source)
  end

  def test_existing_checkout_detection_expands_root
    line = source.lines.find { |row| row.start_with?("if [ -d") && row.include?(".git") }

    assert_equal 'if [ -d "${ROOT}/.git" ]; then', line.strip
    refute_includes line, '\\${ROOT}'
  end
  def test_existing_checkout_origin_is_validated_before_running_project_code
    assert_match(/remote get-url origin/, source)
    assert_match(/refusing to run its installer/, source)
    assert_operator source.index("remote get-url origin"), :<, source.index('cd "$ROOT/MASTER"')
  end

  def test_never_uses_android_shared_storage_for_installation
    refute_match(%r{/storage/emulated/0|/sdcard}, source)
    assert_includes source, 'ROOT="${HOME}/pub5"'
  end

  def test_path_setup_appends_expandable_shell_variables
    path_line = source.lines.find { |line| line.include?("printf") && line.include?(".local/bin") }

    refute_nil path_line
    refute_includes path_line, '\$HOME'
    refute_includes path_line, '\$PATH'
    assert_includes path_line, 'PATH="$HOME/.local/bin:$PATH"'
  end

  def test_migration_filter_removes_only_the_malformed_path_export
    line = source.lines.find { |row| row.start_with?("ruby -e 'path = File.join") }
    refute_nil line
    program = line[/ruby -e '([^']+)'/, 1]
    refute_nil program

    Dir.mktmpdir("termux-path-migration") do |home|
      malformed = %q{export PATH="\$HOME/.local/bin:\$PATH"} + "\n"
      File.write(File.join(home, ".bashrc"), malformed + "export EDITOR=vi\n")
      _output, status = Open3.capture2({ "HOME" => home }, "ruby", "-e", program)
      assert status.success?

      result = File.read(File.join(home, ".bashrc"))
      refute_includes result, malformed
      assert_includes result, "export EDITOR=vi\n"
      assert_equal 0, result.lines.count { |row| row.include?('PATH="$HOME/.local/bin:$PATH"') }
    end
    assert_operator source.index(line), :<, source.index("if ! grep -Fq")
  end

  def test_launcher_forwards_arguments_without_shell_interpolation
    assert_includes source, 'exec ruby bin/master "$@"'
  end

  def test_canonical_mobile_installer_has_a_portable_read_only_demo
    assert_operator mobile_source.index('--demo'), :<, mobile_source.index('command -v pkg')
    assert_includes mobile_source, "no commands run, packages installed, files written, or Git state changed"
    assert_includes mobile_source, "all device and repository checks remain unmeasured"
  end

  def test_mobile_installer_demo_runs_outside_termux_without_creating_files
    Dir.mktmpdir("mobile-install-demo") do |home|
      output, status = Open3.capture2e(
        { "HOME" => home, "MASTER_INSTALL_DIR" => File.join(home, "pub5"), "PREFIX" => "" },
        "sh", MOBILE_INSTALLER, "--demo"
      )

      assert status.success?, output
      assert_includes output, "DEMO only"
      assert_includes output, "plan 5/5"
      assert_includes output, "checks remain unmeasured"
      assert_empty Dir.children(home), "demo mode must not create or modify the target directory"
    end
  end

  def test_mobile_installer_demo_reports_noncanonical_repository_without_mutating
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

  def test_mobile_installer_demo_matches_real_non_git_collision_guard
    Dir.mktmpdir("mobile-install-demo-collision") do |home|
      target = File.join(home, "pub5")
      Dir.mkdir(target)

      output, status = Open3.capture2e(
        { "HOME" => home, "MASTER_INSTALL_DIR" => target },
        "sh", MOBILE_INSTALLER, "--demo"
      )

      refute status.success?
      assert_includes output, "would BLOCK: #{target} exists but is not a Git checkout"
      assert_empty Dir.children(target), "demo must leave the existing directory untouched"
    end
  end

  def test_mobile_installer_installs_and_proves_the_normal_master_bundle
    commands = %w[
      ruby bin/deps install
      ruby bin/deps check
      ruby bin/deps boot
      ruby bin/master-mobile doctor
    ]
    positions = commands.map { |command| mobile_source.index(command) }

    refute positions.any?(&:nil?), "installer must install, check and boot MASTER before declaring readiness"
    assert_equal positions.sort, positions
    assert_includes mobile_source, "cmake pkg-config sqlite libffi"
  end

  def test_mobile_installer_proot_demo_is_opt_in_and_read_only
    Dir.mktmpdir("mobile-proot-demo") do |home|
      output, status = Open3.capture2e(
        { "HOME" => home, "MASTER_INSTALL_DIR" => File.join(home, "pub5"), "PREFIX" => "" },
        "sh", MOBILE_INSTALLER, "--proot", "--demo"
      )

      assert status.success?, output
      assert_includes output, "plan 2/5 - update Termux packages; install git, curl and proot-distro"
      assert_includes output, "install Debian only when no Debian guest exists"
      assert_includes output, "build the exact .ruby-version under /opt/rubies"
      assert_includes output, "all device and repository checks remain unmeasured"
      assert_empty Dir.children(home), "PRoot demo must not create or modify the target directory"
    end
  end

  def test_mobile_installer_provisions_a_pinned_ruby_in_the_debian_guest
    Dir.mktmpdir("mobile-proot-install") do |home|
      target = File.join(home, "pub5")
      bin_dir = File.join(home, "bin")
      Dir.mkdir(target)
      Dir.mkdir(File.join(target, ".git"))
      Dir.mkdir(bin_dir)
      File.write(File.join(target, ".ruby-version"), "4.0.5\n")

      write_stub = lambda do |name, body|
        path = File.join(bin_dir, name)
        File.write(path, "#!/bin/sh\nset -eu\n#{body}\n")
        File.chmod(0o700, path)
      end

      write_stub.call("pkg", 'printf "pkg %s\n" "$*" >> "$CALLS"')
      write_stub.call("id", 'printf "1000\n"')
      write_stub.call("git", <<~'SH')
        [ "$1" = "-C" ] || exit 90
        shift
        shift
        case "$1" in
          remote) printf "https://github.com/anon987654321/pub5.git\n" ;;
          pull|diff) exit 0 ;;
          rev-parse) printf "0123456789abcdef\n" ;;
          *) exit 91 ;;
        esac
      SH
      write_stub.call("proot-distro", <<~'SH')
        case "$1" in
          list)
            if [ "$PROOT_DISTRO_PRESENT" = "1" ]; then
              printf "debian\n"
            fi
            ;;
          install)
            printf "proot-distro %s\n" "$*" >> "$CALLS"
            ;;
          login)
            printf "%s\n" "$@" > "$PROOT_ARGS"
            cat > "$PROOT_GUEST_CAPTURE"
            ;;
          *) exit 92 ;;
        esac
      SH

      calls = File.join(home, "calls.log")
      guest = File.join(home, "guest-setup.sh")
      args = File.join(home, "proot-args.txt")
      env = {
        "HOME" => home,
        "PREFIX" => "/data/data/com.termux/files/usr",
        "MASTER_INSTALL_DIR" => target,
        "CALLS" => calls,
        "PROOT_GUEST_CAPTURE" => guest,
        "PROOT_ARGS" => args,
        "PROOT_DISTRO_PRESENT" => "0",
        "PATH" => [bin_dir, ENV.fetch("PATH", "")].join(File::PATH_SEPARATOR)
      }

      output, status = Open3.capture2e(env, "sh", MOBILE_INSTALLER, "--proot")

      assert status.success?, output
      assert_includes File.read(calls), "pkg install -y git curl proot-distro"
      assert_includes File.read(calls), "proot-distro install debian"
      assert_equal [
        "login", "--bind", "#{target}:/pub5", "debian", "--", "bash", "-s"
      ], File.readlines(args, chomp: true)
      guest_source = File.read(guest)
      assert_includes guest_source, "ruby_version=\"$(cat /pub5/.ruby-version)\""
      assert_includes guest_source, "ruby-build \"$ruby_version\" \"$ruby_home\""
      assert_includes guest_source, 'installed_version="$("$ruby_home/bin/ruby" -e'
      assert_includes guest_source, "ruby bin/deps install"
      assert_includes guest_source, "ruby bin/deps check"
      assert_includes guest_source, "ruby bin/deps boot"
      assert_includes guest_source, "Debian guest setup and CLI boot PASS"
    end
  end

  def test_mobile_installer_uses_posix_shell_syntax
    output, status = Open3.capture2e("sh", "-n", MOBILE_INSTALLER)
    assert status.success?, output
  end

  def test_script_has_valid_bash_syntax
    skip "bash unavailable" unless system("command -v bash >/dev/null 2>&1")

    output, status = Open3.capture2e("bash", "-n", SCRIPT)
    assert status.success?, output
  end
end
