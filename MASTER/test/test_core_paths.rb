# frozen_string_literal: true

require_relative "test_helper"
require "fileutils"

class TestCorePaths < Minitest::Test
  def paths
    Master::Core::Constitution::Paths.new(root: Master::ROOT)
  end

  # Operator decree 2026-11-09: the operator retired the protected-path
  # boundary; nothing is sacred and the declaration list is empty.
  def test_the_operator_decree_retires_the_sacred_paths
    assert_empty paths.sacred_paths
    refute paths.sacred?("data/laws.yml")
    refute paths.sacred?("bin/master")
  end

  def test_authored_fix_code_is_not_sacred
    refute paths.sacred?("lib/fix/fix_loop.rb")
    refute paths.sacred?("lib/core/paths.rb")
  end

  def test_repository_root_resolves_sacred_paths_under_master
    Dir.mktmpdir("core-paths") do |root|
      FileUtils.mkdir_p(File.join(root, "MASTER/data"))
      File.write(
        File.join(root, "MASTER/data/soul.yml"),
        "absolute:\n  sacred_paths:\n    - data/\n    - bin/master\n",
      )
      repo_paths = Master::Core::Constitution::Paths.new(root:)

      assert_includes repo_paths.sacred_paths, "MASTER/data/"
      assert repo_paths.sacred?(File.join(root, "MASTER/data/laws.yml"))
      assert repo_paths.sacred?(File.join(root, "MASTER/bin/master"))
      refute repo_paths.sacred?(File.join(root, "RAILS/app/models/post.rb"))
    end
  end

  # Operator decree 2026-11-09: nothing is sacred, so write_refusal refuses
  # nothing inside the governed MASTER; paths outside it are still not its to judge.
  def test_write_refusal_names_the_reason_from_master_or_the_checkout
    assert_nil Master::Core::Constitution::Paths.write_refusal("data/laws.yml", root: Master::ROOT)
    assert_nil Master::Core::Constitution::Paths.write_refusal("MASTER/data/laws.yml", root: Master::REPO_ROOT)
    assert_nil Master::Core::Constitution::Paths.write_refusal("lib/fix/fix_loop.rb", root: Master::ROOT)
    assert_nil Master::Core::Constitution::Paths.write_refusal("../RAILS/brgen/app/models/post.rb", root: Master::ROOT)
  end

  # A tree with no manifest of its own is held to this MASTER's — which the
  # operator decree of 2026-11-09 retired: nothing is sacred, so no write is
  # refused for sacredness, in the bare tree or in MASTER itself.
  def test_write_refusal_in_a_tree_without_a_manifest
    Dir.mktmpdir("core-paths-bare") do |root|
      assert_nil Master::Core::Constitution::Paths.write_refusal("data/laws.yml", root:)
    end
    assert_nil Master::Core::Constitution::Paths.write_refusal(File.join(Master::ROOT, "data", "soul.yml"))
  end

  def test_path_escape_is_treated_as_protected
    assert paths.sacred?("../outside")
  end

  def test_missing_soul_manifest_fails_closed_for_queries_commits_and_load
    Dir.mktmpdir("core-paths-missing-soul") do |root|
      data_dir = File.join(root, "data")
      FileUtils.mkdir_p(data_dir)
      File.write(File.join(data_dir, "laws.yml"), "{}\n")
      repo_paths = Master::Core::Constitution::Paths.new(root:)

      assert_raises(Errno::ENOENT) { repo_paths.sacred_paths }
      assert repo_paths.sacred?("data/laws.yml")
      assert_includes repo_paths.commit_refusal("data/laws.yml"), "constitution unreadable"
      assert_includes repo_paths.commit_refusal("data/spine.yml"), "constitution unreadable"
      assert_raises(Errno::ENOENT) do
        Master::Core::Constitution.load(data_dir:, workspace_root: root)
      end
    end
  end

  # Operator decree 2026-11-09: an empty declaration retires the boundary —
  # nothing is sacred, nothing is refused for sacredness, and the ratchet
  # ceiling reads the same empty list instead of failing closed.
  def test_empty_sacred_path_declaration_blocks_nothing_including_ratchet_ceiling
    Dir.mktmpdir("core-paths-empty-soul") do |root|
      data_dir = File.join(root, "data")
      FileUtils.mkdir_p(data_dir)
      File.write(File.join(data_dir, "soul.yml"), "absolute:\n  sacred_paths: []\n")
      repo_paths = Master::Core::Constitution::Paths.new(root:)

      assert_empty repo_paths.sacred_paths
      refute repo_paths.sacred?("lib/fix/fix_loop.rb")
      assert_nil repo_paths.commit_refusal("data/spine.yml")
    end
  end

  def test_blank_sacred_path_entries_fail_closed
    Dir.mktmpdir("core-paths-blank-soul") do |root|
      data_dir = File.join(root, "data")
      FileUtils.mkdir_p(data_dir)
      File.write(File.join(data_dir, "soul.yml"), "absolute:\n  sacred_paths:\n    - \"\"\n")
      repo_paths = Master::Core::Constitution::Paths.new(root:)

      assert_raises(Master::Soul::IntegrityError) { repo_paths.sacred_paths }
      assert_includes repo_paths.commit_refusal("data/spine.yml"), "constitution unreadable"
    end
  end

  def test_malformed_soul_manifest_fails_closed
    Dir.mktmpdir("core-paths-malformed-soul") do |root|
      data_dir = File.join(root, "data")
      FileUtils.mkdir_p(data_dir)
      File.write(File.join(data_dir, "soul.yml"), "absolute: [\n")
      repo_paths = Master::Core::Constitution::Paths.new(root:)

      assert repo_paths.sacred?("lib/fix/fix_loop.rb")
      assert_includes repo_paths.commit_refusal("data/spine.yml"), "constitution unreadable"
    end
  end

  def test_unreadable_soul_manifest_fails_closed
    Dir.mktmpdir("core-paths-unreadable-soul") do |root|
      repo_paths = Master::Core::Constitution::Paths.new(root:)
      repo_paths.stub(:sacred_paths, -> { raise Errno::EACCES, "Permission denied" }) do
        assert repo_paths.sacred?("lib/fix/fix_loop.rb")
        assert_includes repo_paths.commit_refusal("data/spine.yml"), "constitution unreadable"
      end
    end
  end

end
