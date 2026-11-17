# frozen_string_literal: true

require "minitest/autorun"

class TestRuntimeOneSource < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def read(path)
    File.read(File.join(ROOT, path), encoding: "UTF-8")
  end

  def test_release_check_delegates_runtime_selection
    source = read("../MASTER/checks/release.rb")
    assert_includes source, 'require_relative "../../MASTER/lib/operator/ruby_runner"'
    assert_includes source, "[Operator::RubyRunner.ruby_cmd]"
    assert_includes source, "Operator::RubyRunner.bundle_cmd"
    refute_match(/\["ruby\d+"\]/, source)
  end

  def test_css_builder_delegates_bundle_selection
    source = read("../MASTER/tools/rails/build_all_css.rb")
    # The tool lives in MASTER/tools/rails, two levels below MASTER/lib.
    assert_includes source, 'require_relative "../../lib/operator/ruby_runner"'
    assert_includes source, "Operator::RubyRunner.bundle_cmd"
    refute_includes source, '["rbenv", "exec", "bundle"]'
  end

  def test_style_check_delegates_bundler_and_ruby
    source = read("../MASTER/tools/style_check.rb")
    assert_includes source, 'require_relative "../lib/operator/ruby_runner"'
    assert_includes source, %([BUNDLE, "exec", RUBY, "-S", "rubocop")
    assert_includes source, %([BUNDLE, "exec", RUBY, shared_rubocop])
    refute_match(/which ruby\d+/, source)
  end
  def test_ruby_selectors_prefer_generic_ruby_and_discover_versioned_packages
    require_relative "../lib/operator/ruby_runner"
    assert_equal ["ruby"], Operator::RubyRunner::RUBY_NAMES
    wrapper = read("bin/ruby")
    openbsd = read("../OPENBSD/lib/ruby_select.sh")
    assert_includes wrapper, 'GENERIC_RUBY=$(command -v ruby'
    assert_includes wrapper, 'for ruby_path in "$directory"/ruby[0-9]*'
    assert_includes openbsd, '_rs_find ruby'
    assert_includes openbsd, '"$_rs_dir"/ruby[0-9]*'
    refute_includes wrapper, "ruby4.3 ruby43 ruby4.2"
    refute_includes openbsd, "ruby4.0 ruby40"
  end
end
