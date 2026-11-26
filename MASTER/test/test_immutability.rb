# frozen_string_literal: true

require_relative "test_helper"

class TestImmutability < Minitest::Test
  ASSET = "RAILS/screenshot_brgen_review.png"

  def test_a_path_escaping_the_root_is_blocked
    Dir.mktmpdir do |root|
      assert Master::Ground::Immutability.new(root:).blocked?("../outside.rb")
    end
  end

  # The sacred-path list retired (operator decree 2026-11-09): nothing but a
  # preserved asset is blocked.
  def test_the_live_tree_blocks_only_preserved_assets
    %w[data/laws.yml data/soul.yml lib/soul.rb data/tokens.yml].each do |path|
      refute Master::Ground::Immutability.blocked?(path), path
    end
    assert Master::Ground::Immutability.blocked?(ASSET, root: Master::REPO_ROOT)
  end

  def test_the_write_switch_never_lifts_a_preserved_asset
    Master::Ground::Immutability.stub(:writes_allowed?, true) do
      assert Master::Ground::Immutability.blocked?(ASSET, root: Master::REPO_ROOT)
      assert Master::Ground::Immutability.new(root: Master::REPO_ROOT).blocked?(ASSET)
    end
  end

  def test_a_preserved_asset_check_that_raises_refuses
    Master::Soul.stub(:preserved_asset?, ->(*, **) { raise IOError, "unreadable" }) do
      assert Master::Ground::Immutability.blocked?("lib/ordinary.rb", root: Master::REPO_ROOT)
      assert Master::Core::Constitution::Paths.write_refusal("lib/ordinary.rb", root: Master::REPO_ROOT)
    end
  end
end
