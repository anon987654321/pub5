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

  def write_proven(dir, relayd: OpenBsdRender.relayd, pf: OpenBsdRender.pf, rc: true)
    Core::Atomic.write(File.join(dir, "relayd.conf"), relayd) if relayd
    Core::Atomic.write(File.join(dir, "pf.conf"), pf) if pf
    return unless rc

    OpenBsdRender.rc.each { |name, text| Core::Atomic.write(File.join(dir, "rc.d", name), text) }
  end

  def test_a_drifted_proven_config_is_a_named_diff_not_a_skip
    Dir.mktmpdir do |dir|
      write_proven(dir, relayd: "tls keypair \"nonsense\"\n")

      diffs = OpenBsdRender.check(dir: dir)

      assert_equal ["relayd.conf: differs from proven"], diffs
    end
  end

  def test_a_missing_proven_fixture_is_a_named_diff
    Dir.mktmpdir do |dir|
      write_proven(dir, pf: nil)

      diffs = OpenBsdRender.check(dir: dir)

      assert_equal 1, diffs.size, "the one missing fixture is named, not skipped"
      assert_includes diffs.first, "pf.conf"
      assert_includes diffs.first, "no proven fixture"
    end
  end

  def web_rows(app, port, extra: [])
    [{ "kind" => "code", "line" => "PORT=#{port}" },
     { "kind" => "code", "line" => "daemon_user=\"#{app}\"" },
     { "kind" => "code", "line" => "APP_DIR=/home/#{app}/app" },
     { "kind" => "code", "line" => "[[ -r /etc/#{app}.env ]] && . /etc/#{app}.env" },
     *extra.map { |line| { "kind" => "code", "line" => line } }]
  end

  def apps_for(**ports)
    ports.keys.map(&:to_s).zip(ports.values).to_h { |app, port| [app, { "port" => port }] }
  end

  def test_a_skeleton_drift_between_two_falcon_scripts_is_named
    scripts = {
      "amber" => { "shape" => "falcon", "rows" => web_rows("amber", 61352, extra: ["free_port || { return 1; }"]) },
      "brgen" => { "shape" => "falcon", "rows" => web_rows("brgen", 38182, extra: ["rc_free_port || { return 1; }"]) },
    }
    diffs = OpenBsdRender.rc_consistency(scripts, apps_for(amber: 61352, brgen: 38182))

    assert_equal ["rc: amber and brgen are both falcon but their code skeletons diverge"], diffs
  end

  def test_the_skeleton_gate_reads_per_app_facts_as_tokens
    scripts = {
      "amber" => { "shape" => "falcon", "rows" => web_rows("amber", 61352) },
      "brgen" => { "shape" => "falcon", "rows" => web_rows("brgen", 38182) },
    }
    diffs = OpenBsdRender.rc_consistency(scripts, apps_for(amber: 61352, brgen: 38182))

    assert_empty diffs, "per-app facts read as tokens, not as divergence"
  end

  def test_web_facts_gate_names_a_port_disagreement
    app = { "port" => 61352, "hosts" => [] }
    script = { "shape" => "falcon", "rows" => [
      { "kind" => "code", "line" => "PORT=47312" },
      { "kind" => "code", "line" => "daemon_user=\"amber\"" },
      { "kind" => "code", "line" => "APP_DIR=/home/amber/app" },
      { "kind" => "comment", "line" => "# . /etc/amber.env is sourced" },
    ] }

    diffs = OpenBsdRender.rc_consistency({ "amber" => script }, { "amber" => app })

    assert_equal ["rc: amber PORT=47312 disagrees with the registry port 61352"], diffs
  end

  def test_non_web_scripts_bind_no_port_and_skip_the_facts_gate
    scripts = {
      "amber_jobs" => { "shape" => "jobs", "rows" => [{ "kind" => "comment", "line" => "# worker" }] },
      "master" => { "shape" => "master", "rows" => [{ "kind" => "code", "line" => "daemon=\"/bin/ksh\"" }] },
    }

    assert_empty OpenBsdRender.rc_consistency(scripts, {})
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
