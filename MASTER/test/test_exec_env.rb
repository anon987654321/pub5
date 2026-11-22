# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/io/exec"
require "rbconfig"

# World hands Exec an env: keyword (credential unsets, chdir, timeout). Spawn
# takes the environment as a leading Hash and rejects env: as an option, so
# every probe and exec died with ArgumentError before this boundary folded
# the keyword into the leading hash.
class TestExecEnv < Minitest::Test
  def test_env_keyword_reaches_the_child
    out, status = Master::Io::Exec.capture2e(
      RbConfig.ruby, "--disable-gems", "-e", "print ENV.fetch('MASTER_EXEC_ENV_TEST', '')",
      env: { "MASTER_EXEC_ENV_TEST" => "child" },
    )
    assert status.success?, out
    assert_equal "child", out
  end

  def test_env_keyword_nil_unsets_an_inherited_name_without_touching_the_parent
    name = "MASTER_EXEC_ENV_TEST"
    previous = ENV[name]
    ENV[name] = "parent"
    out, status = Master::Io::Exec.capture2e(
      RbConfig.ruby, "--disable-gems", "-e", "print ENV.fetch('MASTER_EXEC_ENV_TEST', '')",
      env: { name => nil },
    )
    assert status.success?, out
    assert_empty out
    assert_equal "parent", ENV[name]
  ensure
    previous.nil? ? ENV.delete(name) : ENV[name] = previous
  end

  def test_leading_hash_and_keyword_merge_keyword_wins
    out, status = Master::Io::Exec.capture2e(
      { "MASTER_EXEC_ENV_A" => "lead", "MASTER_EXEC_ENV_B" => "lead" },
      RbConfig.ruby, "--disable-gems", "-e",
      "print [ENV['MASTER_EXEC_ENV_A'], ENV['MASTER_EXEC_ENV_B']].join(',')",
      env: { "MASTER_EXEC_ENV_B" => "keyword" },
    )
    assert status.success?, out
    assert_equal "lead,keyword", out
  end

  def test_world_probe_shape_runs
    out, status = Master::Io::Exec.capture2e("true", env: { "RUBYOPT" => nil }, chdir: Dir.pwd,
                                             timeout: 10, raise_on_timeout: true)
    assert status.success?, out
  end
end
