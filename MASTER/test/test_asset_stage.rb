# frozen_string_literal: true

require_relative "test_helper"
require "shellwords"
require "operator/asset_stage"

# The deploy refuses any MASTER web or Rails release whose public/assets lacks a
# manifest and a .pub5-build-sha naming the pinned commit, and nothing wrote
# either. AssetStage is that writer: built here, staged on the box, per target.
class AssetStageTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  SHA = "a" * 40

  def test_all_stages_every_inventory_app_in_deploy_order
    names = Operator::AssetStage.targets(root: ROOT, app: "all").map(&:name)

    assert_equal "master", names.first
    assert_includes names, "brgen"
    assert_equal names.uniq, names
  end

  def test_master_web_stages_into_devs_checkout_and_rails_into_the_app_home
    master, brgen = %w[master brgen].map { |app| Operator::AssetStage.targets(root: ROOT, app:).first }

    assert_equal ["dev", "/home/dev/pub5/MASTER/web/public/assets"], [master.owner, master.remote_dir]
    assert_equal ["brgen", "/home/brgen/app/public/assets"], [brgen.owner, brgen.remote_dir]
  end

  def test_a_rails_target_unpacks_as_root_and_hands_the_tree_to_the_app_user
    target = Operator::AssetStage.targets(root: ROOT, app: "brgen").first
    script = Shellwords.split(target.unpack_command).last

    assert script.start_with?("set -e; ")
    assert_includes script, "install -d -o brgen /home/brgen/app/public/assets"
    assert script.end_with?("chown -R brgen /home/brgen/app/public/assets")
  end

  def test_the_first_failure_stops_before_any_later_target_is_staged
    staged = []
    stage = Operator::AssetStage.new(root: ROOT, sha: SHA, ssh: %w[ssh host], out: StringIO.new)
    stage.define_singleton_method(:build) { |target| target.name == "brgen" ? [false, "boom"] : [true, nil] }
    stage.define_singleton_method(:upload) { |target| staged << target.name and [true, nil] }

    ok, reason = stage.run("all")

    refute ok
    assert_equal "brgen asset build failed here: boom", reason
    assert_equal ["master"], staged
  end
end
