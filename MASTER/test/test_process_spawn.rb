# frozen_string_literal: true

require_relative "test_helper"

class TestProcessSpawn < Minitest::Test
  def test_environment_scrubs_child_vars_without_mutating_parent_env
    names = %w[MallocStackLogging MallocStackLoggingNoCompact MallocStackLoggingDirectory]
    previous = names.to_h { |name| [name, ENV[name]] }
    parent_values = names.to_h { |name| [name, "parent-#{name}"] }
    parent_values.each { |name, value| ENV[name] = value }

    child_env = Master::Io::ProcessSpawn.environment("ORDINARY_CHILD" => "kept")

    names.each { |name| assert_equal parent_values.fetch(name), ENV[name] }
    names.each { |name| assert_nil child_env[name] }
    assert_equal "kept", child_env.fetch("ORDINARY_CHILD")
  ensure
    names&.each do |name|
      old = previous&.fetch(name)
      old.nil? ? ENV.delete(name) : ENV[name] = old
    end
  end

  def test_spawn_options_do_not_change_parent_environment
    previous = ENV["MallocStackLogging"]
    ENV["MallocStackLogging"] = "parent-value"

    Master::Io::ProcessSpawn.options

    assert_equal "parent-value", ENV["MallocStackLogging"]
  ensure
    previous.nil? ? ENV.delete("MallocStackLogging") : ENV["MallocStackLogging"] = previous
  end
end
