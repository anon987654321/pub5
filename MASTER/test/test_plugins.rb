# frozen_string_literal: true

require_relative "test_helper"
require "rbconfig"

class TestPlugins < Minitest::Test
  def test_manifests_have_local_policy
    manifests = Master::Plugin.list
    assert_equal %w[air_superiority design_calibration session_browser social_browser tap_probes travel_browser tts_dsp video_recordings], manifests.map(&:id)
    manifests.each { |manifest| assert Master::Plugin.policy(manifest.id).is_a?(Hash) }
  end

  def test_session_browser_policy_is_closed_by_default
    policy = Master::Plugin.policy("session_browser")
    assert_equal [], policy.fetch("allowed_hosts")
    assert_equal [true, false], [policy.fetch("session_host_bound"), policy.fetch("security_challenge_bypass")]

    plugin = Master::Plugin.load("session_browser")
    result = plugin.call(action: "status")
    assert_equal "blocked: no allowed hosts configured", result.fetch(:policy)
    assert_equal 4, result.fetch(:max_sessions)
    assert_equal %w[GET HEAD], result.fetch(:allowed_network_methods)
    assert_equal true, result.fetch(:page_scripts_execute)
    assert_equal true, result.fetch(:request_side_effects_possible)
    assert_equal "blocked", result.fetch(:form_submission)
  end

  def test_session_browser_refuses_hosts_until_operator_allowlists_them
    plugin = Master::Plugin.load("session_browser")
    assert_raises(Master::Plugin::PolicyError) do
      plugin.send(:validate_url!, "https://example.com/")
    end
  end

  def test_session_browser_normalizes_the_same_www_host_consistently
    plugin = Master::Plugin.load("session_browser")
    assert_equal "example.com", plugin.send(:canonical_host, "WWW.Example.com.")
  end

  def test_session_browser_screenshot_action_is_not_observable
    assert_equal %w[status inspect], Master::Plugin.info("session_browser").observe_actions
    assert_raises(Master::Plugin::PolicyError) do
      Master::Plugin.observe("session_browser", action: "look")
    end
  end

  def test_social_sites_are_fixed_and_https_only
    plugin = Master::Plugin.load("social_browser")
    result = plugin.call(action: "status")
    assert_equal %w[onlyfans fetlife], result[:sites].map { |site| site[:id] }
    assert_includes %w[ferrum unavailable], result[:browser]
  end

  def test_travel_status_exposes_hard_purchase_check
    result = Master::Plugin.load("travel_browser").call(action: "status")
    assert_equal true, result[:final_purchase_check]
    assert_equal true, result[:sensitive_fields_manual]
    assert_includes %w[ferrum unavailable], result[:browser]
  end

  def test_travel_final_purchase_requires_explicit_confirmation
    plugin = Master::Plugin.load("travel_browser")
    assert_raises(Master::Plugin::PolicyError) do
      plugin.call(action: "book", session: "test", selector: "button[type=submit]", confirm_purchase: false)
    end
  end

  def test_travel_rejects_non_https
    plugin = Master::Plugin.load("travel_browser")
    assert_raises(Master::Plugin::PolicyError) do
      plugin.call(action: "open", session: "test", url: "http://example.com")
    end
  end

  def test_travel_blocks_sensitive_fill_fields
    plugin = Master::Plugin.load("travel_browser")
    assert_raises(Master::Plugin::PolicyError) do
      plugin.call(action: "fill", session: "test", selector: "input[name=card_number]", value: "4111111111111111")
    end
  end

  def test_social_does_not_admit_unsolicited_actions
    plugin = Master::Plugin.load("social_browser")
    assert_raises(Master::Plugin::PolicyError) do
      plugin.call(
        action: "publish_owned",
        site: "onlyfans",
        account: "test",
        url: "https://onlyfans.com",
        message: "x",
        consent: true,
        owned_account: false,
      )
    end
  end

  def test_air_command_capture_merges_output_and_status
    plugin = Master::Plugin.load("air_superiority")
    argv, status, output = plugin.send(:capture, [RbConfig.ruby, "-e", "STDOUT.write('out'); STDERR.write('err')"])

    assert_equal [RbConfig.ruby, "-e", "STDOUT.write('out'); STDERR.write('err')"], argv
    assert status.success?
    assert_includes output, "out"
    assert_includes output, "err"
  end

  def test_air_command_capture_times_out_without_waiting_for_the_child
    plugin = Master::Plugin.load("air_superiority")
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    error = assert_raises(Master::Plugin::Error) do
      plugin.send(:capture, [RbConfig.ruby, "-e", "sleep 10"], timeout: 0.1)
    end

    assert_match(/command timed out/, error.message)
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 3
  end

  def test_air_refuses_unknown_actions
    plugin = Master::Plugin.load("air_superiority")
    assert_raises(Master::Plugin::PolicyError) { plugin.call(action: "inject") }
  end

  def test_air_runtime_is_truthful
    result = Master::Plugin.load("air_superiority").call(action: "status")
    assert result[:runtime]
    assert result[:wifi]
    assert result[:bluetooth]
  end

  def test_air_scan_marks_partial_results_explicitly
    plugin = Master::Plugin.load("air_superiority")
    result = plugin.send(:scan)
    assert_includes [true, false], result[:complete]
    assert result[:observed_at]
    assert_equal result[:wifi].length, result[:counts][:wifi]
    assert_equal result[:bluetooth].length, result[:counts][:bluetooth]
  end

  def test_air_analysis_uses_normalized_findings
    analyzer = Master::Plugins::AirSuperioritySupport::Analyzer.new(observed_at: Time.at(0).utc)
    findings = analyzer.wifi([{ "bssid" => "AA:BB:CC:DD:EE:FF", "ssid" => "test" }], [])
    assert_equal "unknown_wifi", findings.first.kind
    assert_equal "advisory", findings.first.severity
    assert_equal Time.at(0).utc, findings.first.observed_at
  end

  def test_observable_actions_are_declared_by_manifest
    assert_equal %w[status inspect], Master::Plugin.info("social_browser").observe_actions
    assert_equal %w[status inspect], Master::Plugin.info("travel_browser").observe_actions
    assert_equal %w[status scan], Master::Plugin.info("air_superiority").observe_actions
  end

  def test_observe_rejects_mutating_plugin_actions
    assert_raises(Master::Plugin::PolicyError) do
      Master::Plugin.observe("social_browser", action: "publish_owned")
    end
    assert_raises(Master::Plugin::PolicyError) do
      Master::Plugin.observe("travel_browser", action: "book")
    end
  end

  def test_plugin_observe_adapter_returns_observation_result
    governor = Object.new
    governor.define_singleton_method(:permit?) { |*| Master::Result.ok(true) }
    tool = Master::Io::PluginObserve.new(governor:, event_bus: nil)
    result = tool.call(plugin: "air_superiority", action: "status", args: {})
    assert result.ok?
    assert_equal "air_superiority", result.value!.fetch(:plugin)
  end

  def test_plugin_observe_rejects_non_object_arguments
    governor = Object.new
    governor.define_singleton_method(:permit?) { |*| Master::Result.ok(true) }
    tool = Master::Io::PluginObserve.new(governor:, event_bus: nil)
    result = tool.call(plugin: "air_superiority", action: "status", args: [])
    refute result.ok?
    assert_equal :validation, result.category
  end
  # login used to quit the browser right after its screenshot, so there was nothing to log
  # into. It now holds the window until the operator closes it or the hold runs out.
  def test_login_holds_until_the_window_is_closed_and_a_zero_hold_returns_at_once
    require "ferrum"
    plugin = Master::Plugin.load("social_browser")
    untouched = Object.new
    untouched.define_singleton_method(:current_url) { raise "a zero hold must not poll the page" }
    closed = Object.new
    closed.define_singleton_method(:current_url) { raise Ferrum::Error, "window closed" }

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    plugin.send(:wait_for_operator, untouched, 0)
    plugin.send(:wait_for_operator, closed, 60)

    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 10
  end

  # The Core broker must reach every adapter that used to launch Chromium itself,
  # so no plugin keeps a private process path once a broker is threaded in. A fake
  # broker records the open/close pair and returns a lease whose CDP URL is never
  # dialled, because the assertions are about ownership, not navigation.
  class FakeBroker
    Lease = Data.define(:id, :host, :cdp_url)
    attr_reader :opened, :closed

    def initialize
      @opened = []
      @closed = []
    end

    def open(host:, url: nil, ttl_seconds: nil, profile: nil, persistent: false, headless: true)
      id = "lease-#{@opened.size + 1}"
      @opened << { host:, url:, profile:, persistent:, headless: }
      Lease.new(id:, host:, cdp_url: "ws://127.0.0.1:9/#{id}")
    end

    def close(id)
      @closed << id
      true
    end
  end

  # A stand-in for Ferrum::Browser that spawns nothing and answers the two calls a
  # plugin's with_browser makes: create_page and quit.
  def fake_browser
    page = Object.new
    page.define_singleton_method(:go_to) { |_| }
    browser = Object.new
    browser.define_singleton_method(:create_page) { page }
    browser.define_singleton_method(:quit) { true }
    browser
  end

  # Ferrum is an optional dependency; these tests stub its constructor, so load it
  # (and its error classes) only when present, then swap the constant.
  def with_fake_ferrum_browser(browser)
    require "ferrum"
    fake = Object.new
    fake.define_singleton_method(:new) { |**| browser }
    original = Ferrum::Browser
    Ferrum.send(:remove_const, :Browser)
    Ferrum.const_set(:Browser, fake)
    yield
  ensure
    Ferrum.send(:remove_const, :Browser)
    Ferrum.const_set(:Browser, original)
  end

  def test_session_browser_leases_its_process_from_the_injected_broker
    broker = FakeBroker.new
    plugin = Master::Plugin.load("session_browser", services: { browser_broker: broker })
    plugin.define_singleton_method(:require_ferrum!) { true }
    plugin.define_singleton_method(:transport) do
      Object.new.tap { |t| t.define_singleton_method(:secure_page) { |*, **| true } }
    end

    with_fake_ferrum_browser(fake_browser) do
      plugin.send(:with_browser, Dir.mktmpdir, "example.com", headless: true) { |_| }
    end

    assert_equal "example.com", broker.opened.first[:host]
    assert_equal ["lease-1"], broker.closed
  end

  def test_travel_browser_leases_from_the_broker_once_it_has_a_host
    broker = FakeBroker.new
    plugin = Master::Plugin.load("travel_browser", services: { browser_broker: broker })
    plugin.define_singleton_method(:require_ferrum!) { true }
    plugin.define_singleton_method(:session_root) { Dir.mktmpdir }

    with_fake_ferrum_browser(fake_browser) do
      plugin.send(:with_browser, session: "trip", headless: false, url: "https://example.com/book") { |_| }
    end

    assert_equal "example.com", broker.opened.first[:host]
    assert_equal ["lease-1"], broker.closed
  end

  def test_travel_browser_does_not_lease_a_session_with_no_known_host
    broker = FakeBroker.new
    plugin = Master::Plugin.load("travel_browser", services: { browser_broker: broker })
    plugin.define_singleton_method(:require_ferrum!) { true }
    plugin.define_singleton_method(:session_root) { Dir.mktmpdir }

    with_fake_ferrum_browser(fake_browser) do
      plugin.send(:with_browser, session: "trip", headless: false) { |_| }
    end

    assert_empty broker.opened
    assert_empty broker.closed
  end

  def test_social_browser_leases_the_provider_host_from_the_broker
    broker = FakeBroker.new
    plugin = Master::Plugin.load("social_browser", services: { browser_broker: broker })
    plugin.define_singleton_method(:require_ferrum!) { true }
    plugin.define_singleton_method(:resolve_runtime) { |_| "linux" }
    plugin.define_singleton_method(:account_root) { Dir.mktmpdir }

    with_fake_ferrum_browser(fake_browser) do
      plugin.send(:with_browser, site: "fetlife", account: "me",
                                 url: "https://fetlife.com/home", headless: true, runtime: "linux") { |_| }
    end

    assert_equal "fetlife.com", broker.opened.first[:host]
    assert_equal ["lease-1"], broker.closed
  end
end
