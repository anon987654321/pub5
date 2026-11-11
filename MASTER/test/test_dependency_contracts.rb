# frozen_string_literal: true

require_relative "test_helper"

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

end
