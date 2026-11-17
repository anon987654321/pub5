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

    %w[3.3.8 3.4.9 4.0.5 4.0.7 4.1.0 4.2.0].each { |version| assert ok.(version), version }
    refute ok.("3.2.9")
  end

  def test_wrapper_has_no_artificial_upper_version
    source = File.read(BIN)
    assert_includes source, "MIN_MAJOR=3\nMIN_MINOR=3"
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

  # A build left by an older RUBY_VER must not be trusted blind: a 3.2.x build
  # answered here and then failed Bundler's own `ruby ">= 3.3"` check.
  def test_dev_bootstrap_ignores_a_prior_build_below_the_floor
    Dir.mktmpdir do |dir|
      master = staged_master_with_tools_ruby(dir, version: "3.2.6", marker: "STALE-BUILT")
      FileUtils.cp(File.join(MASTER, "bin", "dev-bootstrap"), File.join(master, "bin", "dev-bootstrap"))

      out, status = Open3.capture2e({ "PATH" => "/usr/bin:/bin", "PUB5_RUBY" => nil,
                                      "MASTER_RUBY_CANDIDATES" => "",
                                      "MASTER_DEV_BOOTSTRAP_BUILD" => "0" },
                                    File.join(master, "bin", "dev-bootstrap"), "-v")

      refute status.success?, "a 3.2 build is below the Gemfile floor and must be refused"
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
