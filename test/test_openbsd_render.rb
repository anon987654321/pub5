# frozen_string_literal: true

# The OPENBSD renderer's rules: the registry generates the proven configs
# byte for byte (comments included - they are where the proven decisions
# live), and the two registries agree on every app fact the configs name.

require "minitest/autorun"
require "tmpdir"
require_relative "../core/core"
require_relative "../lib/openbsd/render"

class TestOpenBsdRender < Minitest::Test
  def test_relayd_renders_the_proven_bytes
    actual = OpenBsdRender.relayd
    expected = File.read(File.join(OpenBsdRender::PROVEN, "relayd.conf"))

    assert_equal expected, actual
  end

  def test_pf_renders_the_proven_bytes
    actual = OpenBsdRender.pf
    expected = File.read(File.join(OpenBsdRender::PROVEN, "pf.conf"))

    assert_equal expected, actual
  end

  def test_the_check_passes_when_the_registry_matches_the_proven
    assert_empty OpenBsdRender.check
  end

  def test_a_drifted_proven_config_is_a_named_diff_not_a_skip
    Dir.mktmpdir do |dir|
      Core::Atomic.write(File.join(dir, "relayd.conf"), "tls keypair \"nonsense\"\n")
      Core::Atomic.write(File.join(dir, "pf.conf"), OpenBsdRender.pf)

      diffs = OpenBsdRender.check(dir: dir)

      assert_equal ["relayd.conf: differs from proven"], diffs
    end
  end

  def test_a_missing_proven_fixture_is_a_named_diff
    Dir.mktmpdir do |dir|
      Core::Atomic.write(File.join(dir, "relayd.conf"), OpenBsdRender.relayd)

      diffs = OpenBsdRender.check(dir: dir)

      assert_equal 1, diffs.size
      assert_includes diffs.first, "pf.conf"
      assert_includes diffs.first, "no proven fixture"
    end
  end

  def test_every_rendered_host_match_serves_a_host_the_registry_answers
    apps = OpenBsdRender.configured_apps
    text = OpenBsdRender.relayd

    known = apps.values.flat_map { |app| app["hosts"] }
    rendered = text.scan(/^  match request header "Host" value "([^"]+)"/).flatten
    assert_operator rendered.size, :>=, 14, "the recorded serving facts carry brgen's nine hosts at least"
    rendered.each do |host|
      assert_includes known, host, "a Host match serves what no registry row answers"
    end
  end

  def test_every_registered_app_serves_on_its_port_behind_one_health_check
    apps = OpenBsdRender.apps["apps"]
    forwards = OpenBsdRender.registry["relayd"]["relay"]["forwards"]

    assert_equal apps.keys.size, forwards.size
    apps.each do |name, app|
      forward = forwards.find { |f| f["app"] == name }

      assert_equal app["port"], forward["port"]
      assert_equal "/up", forward["path"]
      assert_equal 200, forward["code"]
    end
  end

  def test_the_city_keypairs_name_no_host_match_by_decision
    # The proven oshlo note: a city apex needs a keypair, no Host match - the
    # final pass falls through to brgen. The renderer must not invent one.
    text = OpenBsdRender.relayd

    assert_operator text.scan(/^  tls keypair "(\S+)"/).flatten.size, :>=, 11
    %w[oshlo.no stvanger.no trndheim.no cardff.uk edinbrgh.uk frankfrt.de].each do |city|
      refute text.include?("value \"#{city}\""),
             "city #{city} must keep falling through the final pass"
    end
  end
end
