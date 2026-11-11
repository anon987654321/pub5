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

  def test_supported_ruby_floor_has_no_artificial_upper_bound
    window = Operator::Environment
    ok = ->(version) { window::SUPPORTED_RUBY_MIN <= Gem::Version.new(version) }

    %w[3.3.8 3.4.9 4.0.5 4.0.7 4.1.0 4.2.0].each { |version| assert ok.(version), version }
    refute ok.("3.2.9")
  end

  def test_wrapper_has_no_artificial_upper_version
    source = File.read(BIN)
    assert_includes source, "MIN_MAJOR=3\\nMIN_MINOR=3"
    refute_includes source, "MAX_MAJOR="
  end

  def test_it_execs_a_ruby_with_the_arguments_intact
    out, err, status = unbundled { Open3.capture3(BIN, "-e", "print RUBY_VERSION, ' ', ARGV.join(',')", "--", "a b", "c") }

    assert status.success?, err
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

  def test_missing_ruby_pin_uses_available_ruby
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

  def test_rbenv_candidates_are_not_selected_by_a_repo_pin
    old_path = ENV["PATH"]
    old_fake_path = ENV["FAKE_RBENV_PATH"]
    old_rbenv_root = ENV["RBENV_ROOT"]

    Dir.mktmpdir do |root|
      fake_bin = File.join(root, "bin")
      FileUtils.mkdir_p(fake_bin)
      ruby_path = File.join(root, "ruby-4.0.5")
      File.write(ruby_path, "#!/usr/bin/env ruby\n")
      File.chmod(0o755, ruby_path)
      rbenv = File.join(fake_bin, "rbenv")
      File.write(rbenv, <<~RUBY)
        #!/usr/bin/env ruby
        abort "wrong version" unless ENV["RBENV_VERSION"] == "4.0.5"
        puts ENV.fetch("FAKE_RBENV_PATH")
      RUBY
      File.chmod(0o755, rbenv)
      File.write(File.join(root, ".ruby-version"), "4.0.5\n")

      ENV["PATH"] = "#{fake_bin}#{File::PATH_SEPARATOR}#{old_path}"
      ENV["FAKE_RBENV_PATH"] = ruby_path
      ENV["RBENV_ROOT"] = File.join(root, "empty-rbenv")

      assert_equal ruby_path, Operator::RubyRunner.rbenv_path("ruby", root:)
    ensure
      ENV["PATH"] = old_path
      ENV["FAKE_RBENV_PATH"] = old_fake_path
      ENV["RBENV_ROOT"] = old_rbenv_root
    end
  end

  def test_a_failing_script_keeps_its_exit_status
    _, _, status = unbundled { Open3.capture3(BIN, "-e", "exit 7") }

    assert_equal 7, status.exitstatus
  end

  private

  # The suite runs under bundle exec; the Ruby bin/ruby picks may not share that
  # bundle, so the child gets a clean environment.
  def unbundled(&) = defined?(Bundler) ? Bundler.with_unbundled_env(&) : yield
end
