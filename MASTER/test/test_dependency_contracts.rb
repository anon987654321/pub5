# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/boot/dependency_manager"

class TestDependencyContracts < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  REPO = File.expand_path("../..", __dir__)

  def test_reek_dependency_is_declared_for_reek_rule
    gemfile = File.read(File.join(ROOT, "Gemfile"))
    lockfile = File.read(File.join(ROOT, "Gemfile.lock"))

    assert_includes gemfile, 'gem "reek", "~> 6.4", require: false'
    assert_match(/^    reek \(/, lockfile)
    assert_match(/^  reek \(~> 6\.4\)/, lockfile)
  end

  def test_prism_dependency_matches_supported_ruby_language_support
    require "prism"

    assert_operator Gem::Version.new(Prism::VERSION), :>=, Gem::Version.new("1.7.0")
    assert_operator Operator::Environment::SUPPORTED_RUBY_MIN, :<=, Gem::Version.new(RUBY_VERSION)
  end

  def test_rubocop_does_not_pin_a_ruby_patch
    paths = [
      File.join(ROOT, ".rubocop.yml"),
      File.join(REPO, "RAILS", "__shared", ".rubocop.yml"),
    ]

    paths.each do |path|
      refute_match(/TargetRubyVersion:/, File.read(path),
                   "#{path} must accept the installed compatible Ruby")
    end
  end

  def test_repository_does_not_pin_an_exact_ruby_patch
    pins = Dir[File.join(REPO, "{,MASTER/,MASTER/web/,RAILS/*/}.ruby-version")]
    assert_empty pins, "Ruby patch pins must not return: #{pins.inspect}"

    [File.join(ROOT, "Gemfile.lock"), File.join(REPO, "MASTER", "web", "Gemfile.lock")].each do |lock|
      refute_match(/^RUBY VERSION\n/, File.read(lock), "#{lock} must not pin an interpreter")
    end
  end

  # The default home is ephemeral under some roots (a container HOME is wiped on
  # restart). MASTER_DEPENDENCY_HOME points the gem store at persistent storage
  # without editing code; an explicit `home:` still wins.
  def test_dependency_home_override_moves_the_gem_store
    Dir.mktmpdir("master-deps-") do |dir|
      manager = Master::Boot::DependencyManager.new(root: ROOT, out: StringIO.new,
                                                    env: { "PATH" => ENV.fetch("PATH"),
                                                           "MASTER_DEPENDENCY_HOME" => dir })

      assert_match(/\A#{Regexp.escape(dir)}/, manager.send(:bundle_config_root).to_s)
    end
  end

  def test_explicit_home_wins_over_the_dependency_home_override
    Dir.mktmpdir("master-deps-") do |dir|
      manager = Master::Boot::DependencyManager.new(root: ROOT, out: StringIO.new, home: dir,
                                                    env: { "PATH" => ENV.fetch("PATH"),
                                                           "MASTER_DEPENDENCY_HOME" => "/somewhere/else" })

      assert_match(/\A#{Regexp.escape(dir)}/, manager.send(:bundle_config_root).to_s)
    end
  end

end
