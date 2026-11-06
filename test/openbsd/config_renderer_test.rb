# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../lib/openbsd/render"

class OpenBSDConfigRendererTest < Minitest::Test
  def setup
    @rendered = {
      "relayd.conf" => OpenBsdRender.relayd,
      "pf.conf" => OpenBsdRender.pf
    }
  end

  def test_relayd_render_matches_proven_and_generated_files
    [OpenBsdRender::PROVEN, OpenBsdRender::GENERATED].each do |directory|
      assert_equal File.binread(File.join(directory, "relayd.conf")), @rendered.fetch("relayd.conf")
    end
  end

  def test_pf_render_matches_proven_and_generated_files
    [OpenBsdRender::PROVEN, OpenBsdRender::GENERATED].each do |directory|
      assert_equal File.binread(File.join(directory, "pf.conf")), @rendered.fetch("pf.conf")
    end
  end

  def test_every_rc_script_matches_both_file_sets
    OpenBsdRender.rc.each do |name, expected|
      [OpenBsdRender::PROVEN, OpenBsdRender::GENERATED].each do |directory|
        assert_equal File.binread(File.join(directory, "rc.d", name)), expected, "#{directory}/rc.d/#{name}"
      end
    end
  end

  def test_rc_d_file_sets_have_no_missing_or_extra_scripts
    [OpenBsdRender::PROVEN, OpenBsdRender::GENERATED].each do |directory|
      actual = Dir.children(File.join(directory, "rc.d")).sort
      assert_equal OpenBsdRender.rc.keys.sort, actual
    end
  end

  def test_registry_serving_facts_and_rc_skeletons_are_consistent
    configured = OpenBsdRender.configured_apps
    relayd = @rendered.fetch("relayd.conf")
    assert_empty OpenBsdRender.consistency(configured, relayd)
    assert_empty OpenBsdRender.rc_consistency(OpenBsdRender.rc_scripts, configured)
  end

  def test_one_gate_checks_proven_generated_and_serving_facts
    assert_empty OpenBsdRender.check
  end
end
