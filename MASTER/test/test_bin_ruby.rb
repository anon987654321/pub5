# frozen_string_literal: true

require_relative "test_helper"
require "open3"
require "tmpdir"
require "fileutils"
require_relative "../lib/operator/ruby_runner"

# bin/ruby uses the host Ruby first and execs the rest of the line.
# Whichever it picks, the line must run under it with its arguments intact.
class TestBinRuby < Minitest::Test
  BIN = File.expand_path("../bin/ruby", __dir__)
  MASTER = File.expand_path("..", __dir__)

  def test_supported_ruby_floor_has_no_artificial_upper_bound
    window = Operator::Environment
    ok = ->(version) { window::SUPPORTED_RUBY_MIN <= Gem::Version.new(version) }

    %w[3.2.0 3.2.9 3.3.8 3.4.9 4.0.5 4.0.7 4.1.0 4.2.0].each { |version| assert ok.(version), version }
    refute ok.("3.1.9")
  end

  def test_wrapper_has_no_artificial_upper_version
    source = File.read(BIN)
    assert_includes source, "MIN_MAJOR=3\nMIN_MINOR=2"
    refute_includes source, "MAX_MAJOR="
  end

  def test_it_execs_a_ruby_with_the_arguments_intact
    out, err, status = without_cli_verbosity do
      unbundled { Open3.capture3(BIN, "-e", "print RUBY_VERSION, ' ', ARGV.join(',')", "--", "a b", "c") }
    end

    assert status.success?, err
    assert_empty err
    assert_match(/\A\d+\.\d+\.\d+ a b,c\z/, out)
  end

  def test_command_path_finds_executables_on_path_without_a_shell_builtin
    old_path = ENV["PATH"]

    Dir.mktmpdir do |root|
      fake_bin = File.join(root, "bin")
      FileUtils.mkdir_p(fake_bin)
      command = File.join(fake_bin, "ruby")
      File.write(command, "#!/bin/sh\n")
      File.chmod(0o755, command)
      ENV["PATH"] = "#{fake_bin}#{File::PATH_SEPARATOR}#{old_path}"

      assert_equal command, Operator::RubyRunner.command_path("ruby")
    ensure
      ENV["PATH"] = old_path
    end
  end

  def test_wrapper_uses_compatible_path_ruby_when_available
    old_path = ENV["PATH"]
    Dir.mktmpdir do |root|
      fake = File.join(root, "ruby")
      File.write(fake, "#!/bin/sh\nprintf '4.0.5'\n")
      File.chmod(0o755, fake)
      ENV["PATH"] = "#{root}#{File::PATH_SEPARATOR}#{old_path}"
      out, err, status = unbundled { Open3.capture3(BIN, "-e", "print RUBY_VERSION") }
      assert status.success?, err
      assert_equal "4.0.5", out
    end
  ensure
    ENV["PATH"] = old_path
  end

  def test_path_shim_does_not_hide_generic_ruby
    Dir.mktmpdir do |dir|
      bin, host, old, alias_dir = %w[master/bin host old alias].map { |path| File.join(dir, path) }
      [bin, host, old, alias_dir].each { |path| FileUtils.mkdir_p(path) }
      wrapper = File.join(bin, "ruby")
      FileUtils.cp(BIN, wrapper)
      File.symlink(wrapper, File.join(alias_dir, "ruby"))
      [[old, "3.1.9", "OLD"], [host, "4.1.0", "HOST"]].each do |path, version, marker|
        File.write(File.join(path, "ruby"), <<~SH)
          #!/bin/sh
          case " $* " in *" print RUBY_VERSION "*) printf #{version} ;; *) echo #{marker} ;; esac
        SH
        File.chmod(0o755, File.join(path, "ruby"))
      end
      env = { "PATH" => [bin, alias_dir, old, host, "/usr/bin", "/bin"].join(File::PATH_SEPARATOR),
              "PUB5_RUBY" => nil, "HOME" => dir, "RBENV_ROOT" => dir }
      out, err, status = unbundled { Open3.capture3(env, wrapper, "go") }
      assert status.success?, err
      assert_equal "HOST\n", out
    end
  end

  def test_wrapper_rejects_failed_or_malformed_version_probes
    Dir.mktmpdir do |dir|
      fake = File.join(dir, "ruby")
      ["printf 3..8", "printf 3.3.", "printf .3.8", "printf 3.3.8; exit 1"].each do |probe|
        File.write(fake, "#!/bin/sh\n#{probe}\n")
        File.chmod(0o755, fake)
        _, err, status = unbundled { Open3.capture3({ "PUB5_RUBY" => fake }, BIN, "go") }
        refute status.success?, probe
        assert_includes err, "not a compatible Ruby"
      end
    end
  end

  def test_wrapper_leaves_unused_private_ca_directory_untouched
    Dir.mktmpdir do |dir|
      master = staged_master_with_tools_ruby(dir, version: "3.3.6", marker: "PRIVATE")
      wrapper = File.join(master, "bin", "ruby")
      FileUtils.cp(BIN, wrapper)
      host = File.join(dir, "host_ruby")
      File.write(host, "#!/bin/sh\nprintf 3.3.8\n")
      File.chmod(0o755, host)

      out, err, status = unbundled { Open3.capture3({ "PUB5_RUBY" => host }, wrapper, "go") }
      assert status.success?, err
      assert_equal "3.3.8", out
      refute File.exist?(File.join(master, ".tools", "ruby", "ssl"))
    end
  end

  def test_wrapper_selects_private_ruby_without_preexisting_ca_directory
    Dir.mktmpdir do |dir|
      master = staged_master_with_tools_ruby(dir, version: "3.3.6", marker: "PRIVATE")
      wrapper = File.join(master, "bin", "ruby")
      FileUtils.cp(BIN, wrapper)
      private_ruby = File.join(master, ".tools", "ruby", "bin", "ruby")

      out, err, status = unbundled { Open3.capture3({ "PUB5_RUBY" => private_ruby }, wrapper, "go") }
      assert status.success?, err
      assert_includes out, "PRIVATE"
    end
  end

  def test_deleted_running_interpreter_path_is_not_returned_for_child_checks
    Dir.mktmpdir do |dir|
      master = staged_master_with_tools_ruby(dir, version: "3.4.2", marker: "FALLBACK-RUBY")
      stale = File.join(dir, "Cellar", "ruby", "4.0.5", "bin", "ruby")
      FileUtils.mkdir_p(File.dirname(stale))

      Operator::RubyRunner.stub(:config, nil) do
        RbConfig.stub(:ruby, stale) do
          selected = Operator::RubyRunner.best_available_ruby(root: master)

          assert_equal File.join(master, ".tools", "ruby", "bin", "ruby"), selected.fetch(:path)
          refute selected.fetch(:current)
        end
      end
    end
  end

  def test_missing_explicit_ruby_override_is_rejected_without_spawning_it
    missing = File.join(Dir.tmpdir, "pub5-ruby-missing-#{Process.pid}")

    ENV.stub(:[], ->(key) { key == "PUB5_RUBY" ? missing : nil }) do
      error = assert_raises(RuntimeError) { Operator::RubyRunner.ruby_cmd }

      assert_match(/PUB5_RUBY must name an executable Ruby/, error.message)
    end
  end

  def test_runner_finds_private_ruby_from_repository_root
    Dir.mktmpdir do |dir|
      master = staged_master_with_tools_ruby(dir, version: "3.3.6", marker: "PRIVATE")
      assert_equal [File.join(master, ".tools", "ruby", "bin", "ruby")],
                   Operator::RubyRunner.checkout_tools_rubies(dir)
    end
  end

  def test_runner_does_not_trust_rbenv_directory_names_or_failed_probes
    Dir.mktmpdir do |dir|
      path = File.join(dir, "versions", "4.0.1", "bin", "ruby")
      FileUtils.mkdir_p(File.dirname(path))
      ["printf 4.0.1; exit 1", "printf garbage", "printf 3.3.8"].each do |probe|
        File.write(path, "#!/bin/sh\n#{probe}\n")
        File.chmod(0o755, path)
        expected = probe == "printf 3.3.8" ? Gem::Version.new("3.3.8") : nil
        actual = Operator::RubyRunner.version_for(path)
        expected ? assert_equal(expected, actual) : assert_nil(actual)
      end
      File.write(path, "#!/bin/sh\nprintf 3.4.10\n")
      assert_equal Gem::Version.new("3.4.10"), Operator::RubyRunner.version_for(path)
    end
  end

  def test_wrapper_bounds_a_stalled_interpreter_probe
    Dir.mktmpdir do |dir|
      fake = File.join(dir, "ruby")
      File.write(fake, "#!/bin/sh\nexec sleep 30\n")
      File.chmod(0o755, fake)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      _, err, status = unbundled { Open3.capture3({ "PUB5_RUBY" => fake }, BIN, "go") }
      refute status.success?
      assert_includes err, "not a compatible Ruby"
      assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 15
    end
  end

  def test_runner_refuses_unpaired_explicit_ruby_and_invalid_bundle_override
    Dir.mktmpdir do |dir|
      ruby = File.join(dir, "custom-ruby")
      File.write(ruby, "#!/bin/sh\nprintf 3.3.8\n")
      File.chmod(0o755, ruby)
      ENV.stub(:[], ->(key) { { "PUB5_RUBY" => ruby }[key] }) do
        assert_raises(RuntimeError) { Operator::RubyRunner.bundle_cmd }
      end
      ENV.stub(:[], ->(key) { { "PUB5_BUNDLE" => dir }[key] }) do
        assert_raises(RuntimeError) { Operator::RubyRunner.bundle_cmd }
      end
    end
  end

  def test_runner_pairs_bundle_with_explicit_ruby
    Dir.mktmpdir do |dir|
      ruby = File.join(dir, "custom-ruby")
      bundle = File.join(dir, "bundle")
      File.write(ruby, "#!/bin/sh\nprintf 3.3.8\n")
      File.write(bundle, "#!/bin/sh\nexit 0\n")
      [ruby, bundle].each { |path| File.chmod(0o755, path) }
      ENV.stub(:[], ->(key) { { "PUB5_RUBY" => ruby }[key] }) do
        assert_equal bundle, Operator::RubyRunner.bundle_cmd
      end
    end
  end

  def test_running_compatible_interpreter_is_preferred
    selected = Operator::RubyRunner.best_available_ruby
    assert_equal File.expand_path(RbConfig.ruby), File.expand_path(selected.fetch(:path))
    assert_operator selected.fetch(:version), :>=, Operator::Environment::SUPPORTED_RUBY_MIN
  end

  # A Ruby bin/dev-bootstrap built for this checkout sits under MASTER/.tools. It
  # lives on the checkout, unlike a system Ruby under an ephemeral root, so a
  # fresh container with no PATH Ruby must still find it.
  def test_wrapper_discovers_a_checkout_tools_ruby
    Dir.mktmpdir do |dir|
      master = staged_master_with_tools_ruby(dir, version: "3.3.6", marker: "TOOLS-PINNED")
      FileUtils.cp(BIN, File.join(master, "bin", "ruby"))

      out, status = Open3.capture2e({ "PATH" => "/usr/bin:/bin", "PUB5_RUBY" => nil, "HOME" => dir },
                                    File.join(master, "bin", "ruby"), "go")

      assert status.success?, out
      assert_includes out, "TOOLS-PINNED"
    end
  end

  # A build left by an older RUBY_VER must not be trusted blind: a 3.1.x build
  # answered here and then failed Bundler's own `ruby ">= 3.2"` check.
  def test_dev_bootstrap_ignores_a_prior_build_below_the_floor
    Dir.mktmpdir do |dir|
      master = staged_master_with_tools_ruby(dir, version: "3.1.9", marker: "STALE-BUILT")
      FileUtils.cp(File.join(MASTER, "bin", "dev-bootstrap"), File.join(master, "bin", "dev-bootstrap"))

      out, status = Open3.capture2e({ "PATH" => "/usr/bin:/bin", "PUB5_RUBY" => nil,
                                      "MASTER_RUBY_CANDIDATES" => "",
                                      "MASTER_DEV_BOOTSTRAP_BUILD" => "0" },
                                    File.join(master, "bin", "dev-bootstrap"), "-v")

      refute status.success?, "a 3.1 build is below the Gemfile floor and must be refused"
      refute_includes out, "STALE-BUILT", "an out-of-range prior build was exec'd"
      assert_includes out, "ignoring #{File.join(master, '.tools', 'ruby', 'bin', 'ruby')}"
    end
  end

  def test_a_failing_script_keeps_its_exit_status
    _, _, status = unbundled { Open3.capture3(BIN, "-e", "exit 7") }

    assert_equal 7, status.exitstatus
  end

  def test_verbose_mode_restores_the_interpreter_diagnostic
    old = ENV["MASTER_VERBOSE"]
    ENV["MASTER_VERBOSE"] = "1"
    out, err, status = unbundled { Open3.capture3(BIN, "-e", "exit 0") }

    assert status.success?, err
    assert_match(/ruby0: using installed Ruby/, err)
  ensure
    old.nil? ? ENV.delete("MASTER_VERBOSE") : ENV["MASTER_VERBOSE"] = old
  end

  private

  # A scratch <dir>/MASTER with bin/ and a .tools/ruby/bin/ruby that answers its
  # own RUBY_VERSION probe with +version+ and anything else with +marker+.
  def staged_master_with_tools_ruby(dir, version:, marker:)
    master = File.join(dir, "MASTER")
    tools_bin = File.join(master, ".tools", "ruby", "bin")
    FileUtils.mkdir_p(File.join(master, "bin"))
    FileUtils.mkdir_p(tools_bin)

    File.write(File.join(tools_bin, "ruby"), <<~SH)
      #!/bin/sh
      case " $* " in *" print RUBY_VERSION "*) printf "#{version}" ;; *) echo #{marker} ;; esac
    SH
    File.chmod(0o755, File.join(tools_bin, "ruby"))
    master
  end

  def without_cli_verbosity
    keys = %w[MASTER_DMESG MASTER_VERBOSE MASTER_CLI_VERBOSE MASTER_CLI_TRACE MASTER_QUIET]
    saved = keys.to_h { |key| [key, ENV[key]] }
    keys.each { |key| ENV.delete(key) }
    yield
  ensure
    saved.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  # The suite runs under bundle exec; the Ruby bin/ruby picks may not share that
  # bundle, so the child gets a clean environment.
  def unbundled(&) = defined?(Bundler) ? Bundler.with_unbundled_env(&) : yield
end
