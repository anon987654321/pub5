# frozen_string_literal: true

require_relative "test_helper"
require "fileutils"
require "tmpdir"
require "master"

class MasterPathsTest < Minitest::Test
  def test_paths_resolve_under_master_root
    assert MasterPaths.root.end_with?("/MASTER")
    assert_equal File.expand_path("..", MasterPaths.root), MasterPaths.repo
    assert MasterPaths.data("laws.yml").end_with?("/MASTER/data/laws.yml")
    assert MasterPaths.state("provider_catalog.sqlite3").include?(".master")
  end

  def test_fix_state_is_shared_by_https_and_ssh_clones_of_the_same_remote
    Dir.mktmpdir("master-fix-state") do |repo|
      FileUtils.mkdir_p(File.join(repo, "MASTER"))
      assert system("git", "-C", repo, "init", "-q")
      assert system("git", "-C", repo, "config", "user.name", "State Test")
      assert system("git", "-C", repo, "config", "user.email", "state@example.test")
      assert system("git", "-C", repo, "remote", "add", "origin", "https://github.com/anon987654321/pub5.git")
      base = File.join(repo, "shared-state")
      previous_base = ENV["MASTER_STATE_DIR"]
      previous_id = ENV["MASTER_STATE_ID"]
      ENV["MASTER_STATE_DIR"] = base
      ENV.delete("MASTER_STATE_ID")

      https_path = MasterPaths.fix_state(root: File.join(repo, "MASTER"))
      assert_match(%r{/repositories/anon987654321-pub5-[a-f0-9]{12}/fix\z}, https_path)
      assert system("git", "-C", repo, "config", "--replace-all", "remote.origin.url", "git@github.com:anon987654321/pub5.git")
      ssh_path = MasterPaths.fix_state(root: repo)

      assert_equal https_path, ssh_path
      refute_equal File.join(repo, ".master"), https_path
    ensure
      previous_base.nil? ? ENV.delete("MASTER_STATE_DIR") : ENV["MASTER_STATE_DIR"] = previous_base
      previous_id.nil? ? ENV.delete("MASTER_STATE_ID") : ENV["MASTER_STATE_ID"] = previous_id
    end
  end

  def test_non_git_temporary_roots_keep_one_local_state_directory_from_either_tree_root
    Dir.mktmpdir("master-fix-state-local") do |repo|
      FileUtils.mkdir_p(File.join(repo, "MASTER"))
      previous_id = ENV["MASTER_STATE_ID"]
      previous_base = ENV["MASTER_STATE_DIR"]
      ENV.delete("MASTER_STATE_ID")
      ENV.delete("MASTER_STATE_DIR")

      expected = File.join(repo, ".master")
      assert_equal expected, MasterPaths.fix_state(root: repo)
      assert_equal expected, MasterPaths.fix_state(root: File.join(repo, "MASTER"))
    ensure
      previous_id.nil? ? ENV.delete("MASTER_STATE_ID") : ENV["MASTER_STATE_ID"] = previous_id
      previous_base.nil? ? ENV.delete("MASTER_STATE_DIR") : ENV["MASTER_STATE_DIR"] = previous_base
    end
  end
end

class RepoPathsTest < Minitest::Test
  def test_repo_root_is_pub5_monorepo
    assert_equal Master::REPO_ROOT, Master.repo_root
    assert_equal File.expand_path("..", Master::ROOT), Master.repo_root
  end
end

class TestRepoMap < Minitest::Test
  def test_brief_respects_token_budget
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "lib"))
      10.times { |index| File.write(File.join(dir, "lib", "file_#{index}.rb"), "puts :ok\n") }

      rows = Master::Ground::Map::Repo.new(root: dir).brief("file", limit: 10, token_limit: 8)

      assert rows.any?
      assert_operator rows.join("\n").bytesize, :<=, 40
    end
  end
end
