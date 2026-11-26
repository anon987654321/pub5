# frozen_string_literal: true

require_relative "test_helper"
require "fileutils"

class TestCorePaths < Minitest::Test
  PATHS = Master::Core::Constitution::Paths

  # Operator decree 2026-11-09 retired the sacred-path list: the laws, the
  # soul and authored code are refused nowhere.
  def test_the_retired_list_refuses_no_ordinary_path
    %w[data/laws.yml bin/master lib/fix/fix_loop.rb lib/core/paths.rb].each do |path|
      refute PATHS.sacred?(path, root: Master::ROOT), path
      assert_nil PATHS.write_refusal(path, root: Master::ROOT)
    end
    assert_nil PATHS.write_refusal("data/laws.yml")
    assert_nil PATHS.write_refusal(File.join(Master::ROOT, "data", "soul.yml"))
  end

  def test_a_tree_without_a_manifest_refuses_nothing_ordinary
    Dir.mktmpdir("core-paths-bare") do |root|
      assert_nil PATHS.write_refusal("data/laws.yml", root:)
    end
  end

  def test_preserved_project_assets_cover_visual_and_private_lora_material
    [
      "RAILS/screenshot_brgen_review.png",
      "RAILS/amber/screenshots/amber-desktop.png",
      "MASTER/checks/data/route_screenshots/brgen-home.png",
      "STUDIO/lora/johann/sources/portrait-01.jpg",
      "STUDIO/lora/ragnhild/weights/model.safetensors",
      "STUDIO/lora/merethe/dataset/captions.json",
      "STUDIO/lora/johann_selfie_01.jpg",
      "STUDIO/lora/selfies/manifest.js",
    ].each do |path|
      assert Master::Soul.preserved_asset?(path, root: Master::REPO_ROOT), path
      assert PATHS.sacred?(path, root: Master::REPO_ROOT), path
      assert_match(/preserved project asset/, Master::Core::Constitution::Paths.write_refusal(path, root: Master::REPO_ROOT))
    end

    subject_root = File.join(Master::REPO_ROOT, "STUDIO/lora/johann")
    assert Master::Soul.preserved_asset?("sources/portrait.jpg", root: subject_root)
    assert Master::Soul.preserved_asset?("weights/johann/replicate_training.json", root: subject_root)
    assert Master::Soul.preserved_asset?("train.yaml", root: subject_root)

    refute Master::Soul.preserved_asset?("STUDIO/lora/selfie_series.rb", root: Master::REPO_ROOT)
    refute PATHS.sacred?("STUDIO/lora/selfie_series.rb", root: Master::REPO_ROOT)
  end

  def test_preserved_assets_ignore_the_general_write_switch
    Master::Ground::Immutability.stub(:writes_allowed?, true) do
      assert Master::Ground::Immutability.blocked?(
        "RAILS/screenshot_brgen_review.png", root: Master::REPO_ROOT
      )
      assert_match(
        /preserved project asset/,
        Master::Core::Constitution::Paths.write_refusal(
          "RAILS/screenshot_brgen_review.png", root: Master::REPO_ROOT
        )
      )
    end
  end
end
