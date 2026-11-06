# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../core/core"
require_relative "../../openbsd/lib/config_renderer"

class OpenBSDConfigRendererTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)

  def setup
    @renderer = OpenBSD::ConfigRenderer.new(root: ROOT)
  end

  def test_relayd_render_matches_proven_fixture
    assert_equal File.binread(File.join(ROOT, "openbsd/proven/relayd.conf")), @renderer.render.fetch("relayd.conf")
  end

  def test_pf_render_matches_proven_fixture
    assert_equal File.binread(File.join(ROOT, "openbsd/proven/pf.conf")), @renderer.render.fetch("pf.conf")
  end

  def test_every_rc_script_matches_proven_fixture
    files = @renderer.render
    scripts = files.keys.grep(/\Arc\.d\//)
    refute_empty scripts
    scripts.each do |relative|
      assert_equal File.binread(File.join(ROOT, "openbsd/proven", relative)), files.fetch(relative), relative
    end
  end

  def test_generated_mirror_and_approved_fixtures_match_registry
    assert @renderer.check!
  end

  def test_relayd_serving_facts_match_deployed_apps_only
    @renderer.render
    apps = Core::Registry.load(:apps).fetch("apps")
    relay = Core::Registry.load(:openbsd).fetch("relayd")
    expected = apps.each_with_object({}) do |(name, app), result|
      result[name.to_s] = Integer(app.fetch("port")) if app.key?("port")
    end
    actual = relay.fetch("relay").fetch("forwards").to_h do |row|
      [row.fetch("app").to_s, Integer(row.fetch("port"))]
    end

    assert_equal expected, actual
    assert_equal expected.keys.sort, relay.fetch("tables").map(&:to_s).sort
  end
end
