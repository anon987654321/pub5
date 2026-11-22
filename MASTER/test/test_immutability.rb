# frozen_string_literal: true

require_relative "test_helper"

class TestImmutability < Minitest::Test
  def test_blocked_follows_the_declared_sacred_paths
    with_fixture do |root|
      checker = Master::Ground::Immutability.new(root:)
      assert checker.blocked?(File.join(root, "data", "future.yml"))
      assert checker.blocked?("SOUL.md")
      refute checker.blocked?(File.join(root, "lib", "future.rb"))
    end
  end

  def test_a_path_escaping_the_root_is_blocked
    with_fixture do |root|
      assert Master::Ground::Immutability.new(root:).blocked?("../outside.rb")
    end
  end

  # Operator decree 2026-11-09: an empty declaration retires the boundary —
  # nothing is sacred, so no path is blocked.
  def test_an_empty_sacred_manifest_blocks_nothing
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "data"))
      File.write(File.join(root, "data", "soul.yml"), "absolute:\n  sacred_paths: []\n")
      refute Master::Ground::Immutability.new(root:).blocked?("lib/x.rb")
    end
  end

  # Operator decree 2026-11-09: the operator retired the protected-path
  # boundary. No path is sacred, so no automated write is refused for
  # sacredness anywhere in the tree.
  def test_the_live_manifest_blocks_nothing_per_the_operator_decree
    refute Master::Ground::Immutability.blocked?("data/laws.yml")
    refute Master::Ground::Immutability.blocked?("data/soul.yml")
    refute Master::Ground::Immutability.blocked?("lib/soul.rb")
    refute Master::Ground::Immutability.blocked?("data/SOUL.md")
    refute Master::Ground::Immutability.blocked?("data/IDENTITY.md")
    refute Master::Ground::Immutability.blocked?("data/tokens.yml")
  end

  private

  def with_fixture
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "data"))
      File.write(File.join(root, "data", "soul.yml"), "absolute:\n  sacred_paths:\n    - data/\n    - SOUL.md\n")
      File.write(File.join(root, "SOUL.md"), "# soul\n")
      yield root
    end
  end
end
