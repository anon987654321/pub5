# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require_relative "../lib/boot/entrypoint"

class TestBootEntrypoint < Minitest::Test
  SOURCE = File.read(File.expand_path("../lib/boot/entrypoint.rb", __dir__))
  GEMFILE = File.read(File.expand_path("../Gemfile", __dir__))
  LOCKFILE = File.read(File.expand_path("../Gemfile.lock", __dir__))

  def test_json_uses_the_bundle_resolution_not_a_ruby_release_pin
    refute GEMFILE.lines.any? { |line| line.start_with?('gem "json", "=') }
    refute LOCKFILE.lines.any? { |line| line.start_with?("  json (=") }
    assert LOCKFILE.lines.any? { |line| line.start_with?("    json (") }
  end

  def test_json_is_loaded_only_after_bundler_activation
    bundle_index = SOURCE.index("activate_bundle!(root)")
    json_index = SOURCE.index('require "json"')
    refute_nil bundle_index
    refute_nil json_index
    assert_operator json_index, :>, bundle_index
  end

  def test_lockfile_bundler_version_is_read_from_the_master_lock
    Dir.mktmpdir("master-entrypoint") do |root|
      File.write(File.join(root, "Gemfile.lock"), <<~LOCK)
        GEM
          remote: https://rubygems.org/

        DEPENDENCIES

        BUNDLED WITH
          4.0.7
      LOCK

      reader = Master::Boot::Entrypoint.method(:locked_bundler_version)
      assert_equal "4.0.7", reader.call(root)
    end
  end

  def test_supported_ruby_floor_has_no_artificial_upper_bound
    env = Operator::Environment

    %w[3.3.0 3.3.8 3.4.9 4.0.5 4.0.7 4.1.0 4.2.0].each do |version|
      assert env::SUPPORTED_RUBY_MIN <= Gem::Version.new(version), version
    end
    # The Gemfile ("ruby >= 3.3"), the gemspec's required_ruby_version and
    # bin/ruby's MIN_MINOR=3 all gate on 3.3, so the floor is 3.3; 3.2 stays
    # below it.
    assert env::SUPPORTED_RUBY_MIN <= Gem::Version.new("3.3.0")
    refute env::SUPPORTED_RUBY_MIN <= Gem::Version.new("3.2.9")
  end

  def test_inline_program_does_not_reexec_when_the_selected_ruby_version_matches
    candidate = { path: "/different/path/to/ruby", version: Gem::Version.new(RUBY_VERSION) }
    root = File.expand_path("../..", __dir__)

    Operator::RubyRunner.stub(:best_available_ruby, candidate) do
      Master::Boot::Entrypoint.stub(:same_file?, false) do
        assert_nil Master::Boot::Entrypoint.reexec_best_ruby!(
          root:, env: {}, out: StringIO.new, argv: ["-e", "puts :ok"], program: "-e",
        )
      end
    end
  end

  def test_preloaded_wrong_bundler_reexecs_into_a_clean_process
    Dir.mktmpdir("master-entrypoint") do |root|
      program = write_boot_script(root, "bin", "master", executable: true)
      env = {
        "RUBYOPT" => "-rbundler/setup",
        "RUBYLIB" => "/wrong/bundler/lib",
        "BUNDLE_GEMFILE" => "/wrong/Gemfile",
        "BUNDLE_LOCKFILE" => "/wrong/Gemfile.lock",
      }

      clean, rest, options = capture_reexec(root:, env:, program:)

      assert_equal [program, "--fast"], rest
      assert_equal({ unsetenv_others: true }, options)
      assert_equal "1", clean["MASTER_BUNDLER_REEXEC_DONE"]
      refute clean.key?("RUBYOPT")
      refute clean.key?("RUBYLIB")
      refute clean.key?("BUNDLE_GEMFILE")
      refute clean.key?("BUNDLE_LOCKFILE")
    end
  end

  def test_reexec_of_a_non_executable_script_prefixes_the_interpreter
    Dir.mktmpdir("master-entrypoint") do |root|
      # `ruby tools/x.rb` leaves no executable bit; a bare exec would EACCES.
      program = write_boot_script(root, "tools", "boot_smoke.rb", executable: false)

      _clean, rest, _options = capture_reexec(root:, env: {}, program:)

      assert_equal [RbConfig.ruby, program, "--fast"], rest
    end
  end

  private

  # A scratch checkout with the lock reexec_mismatched_bundler! reads, and the
  # program it would re-exec, executable or not.
  def write_boot_script(root, *segments, executable:)
    File.write(File.join(root, "Gemfile"), "source \"https://rubygems.org\"\n")
    File.write(File.join(root, "Gemfile.lock"), <<~LOCK)
      GEM
        remote: https://rubygems.org/

      DEPENDENCIES

      BUNDLED WITH
        4.0.5
    LOCK
    program = File.join(root, *segments)
    FileUtils.mkdir_p(File.dirname(program))
    File.write(program, executable ? "#!/usr/bin/env ruby\n" : "puts :ok\n")
    File.chmod(executable ? 0o755 : 0o644, program)
    program
  end

  # [clean_env, argv, options] from the re-exec, with exec and Bundler's active
  # version stubbed so no process is replaced.
  def capture_reexec(root:, env:, program:)
    active = Struct.new(:version).new(Gem::Version.new("4.0.7"))
    captured = nil

    Master::Boot::Entrypoint.stub(:exec, ->(clean, *rest, **options) { captured = [clean, rest, options] }) do
      Gem.stub(:loaded_specs, { "bundler" => active }) do
        Master::Boot::Entrypoint.reexec_mismatched_bundler!(
          root:, env:, out: StringIO.new, argv: ["--fast"], program:,
        )
      end
    end

    refute_nil captured
    captured
  end
end
