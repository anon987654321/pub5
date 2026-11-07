# frozen_string_literal: true

require "minitest/autorun"

class TestTriangleRuntimeContract < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  SOURCE = File.read(File.join(ROOT, "..", "MASTER", "tools", "rails", "triangle.rb"), encoding: "UTF-8")

  def test_triangle_uses_the_shared_runtime
    assert_includes SOURCE, 'require_relative "../../lib/operator/ruby_runner"'
    # The runner prefers the project-pinned rbenv Ruby and falls back to
    # ruby_cmd: a Homebrew Ruby of the same version carried gems the apps do
    # not have, and every boot died in db:prepare (2026-11-07).
    assert_includes SOURCE, 'RUBY = Operator::RubyRunner.rbenv_path("ruby") || Operator::RubyRunner.ruby_cmd'
    assert_includes SOURCE, 'BUNDLE = Operator::RubyRunner.rbenv_path("bundle") || Operator::RubyRunner.bundle_cmd'
    refute_includes SOURCE, '"rbenv", "exec"'
  end

  def test_migrate_and_boot_run_the_pinned_ruby_inside_bundle
    assert_includes SOURCE, 'BUNDLE, "exec", RUBY, "bin/rails", "db:prepare"'
    assert_includes SOURCE, 'BUNDLE, "exec", RUBY, "bin/rails", "server"'
  end

  def test_triangle_does_not_boot_after_a_failed_migration
    assert_includes SOURCE, 'unless migrate(app)'
    assert_includes SOURCE, 'failed << app[:name]'
    assert_includes SOURCE, 'next'
  end
end
