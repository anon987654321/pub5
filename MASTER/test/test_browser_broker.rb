# frozen_string_literal: true

require_relative "test_helper"

# The broker is the one owner of a Chromium process and its session lease, so
# its contract is the boundary an adapter cannot cross: it may not start a
# browser without the capability, may not attach to or stop a lease it did not
# receive, may not widen the host it was bound to, and may not leave a child
# process behind when the conversation ends. Every case below drives a real
# broker against a scripted engine, so the assertions are about the broker's own
# decisions rather than about Chromium.
class BrowserBrokerTest < Minitest::Test
  Broker = Master::Io::BrowserBroker
  Caps = Master::Core::Capabilities

  # A scripted engine: records start/stop calls and hands back a handle whose
  # fields the broker treats as opaque. No process, no CDP, no Chrome.
  class FakeEngine
    attr_reader :started, :stopped

    def initialize(cdp_url: "ws://127.0.0.1:9222/devtools/browser/fake", fail_on_start: false)
      @started = []
      @stopped = []
      @cdp_url = cdp_url
      @fail_on_start = fail_on_start
    end

    def start(host:, lease_id:, profile: nil, persistent: false, headless: true)
      raise Broker::Denied, "engine refused" if @fail_on_start

      @started << { host:, lease_id:, profile:, persistent:, headless: }
      Broker::Handle.new(pid: 4242, pgroup: true, cdp_url: @cdp_url,
                         profile_dir: profile || "/tmp/fake-#{lease_id}", host:,
                         persistent:)
    end

    def stop(handle)
      @stopped << handle
      true
    end
  end

  def broker(capabilities: Caps.for(:fix), engine: FakeEngine.new, ledger: nil, **opts)
    Broker.new(capabilities:, engine:, ledger:, **opts)
  end

  def test_only_corebridge_builds_a_broker_from_the_current_capability_set
    builder = File.read(File.join(Master::ROOT, "lib", "builder.rb"))
    bridge = File.read(File.join(Master::ROOT, "lib", "cli", "core_bridge.rb"))

    refute_includes builder, "build_browser_broker"
    refute_includes builder, "Capabilities.for(:fix)"
    assert_includes bridge, "return nil unless capabilities.allow?(:browser)"
    assert_includes bridge, "Master::Io::BrowserBroker.new("
    assert_includes bridge, "capabilities:,"
    assert_includes bridge, "browser_scope.with(browser, &fold)"
    assert_includes builder, "browser_broker: Io::BrowserBroker::Scope.new"
  end

  def test_all_six_production_adapters_attach_only_to_broker_issued_leases
    adapters = {
      "lib/io/web_browse.rb" => ["@broker.open", "Core-owned browser broker is unavailable"],
      "lib/io/browser_agent.rb" => ["@broker.open", "Core-owned browser broker is unavailable"],
      "lib/io/web_chat.rb" => ["@broker.open", "Core-owned browser broker is unavailable"],
      "plugins/session_browser/session_browser.rb" => ["owner.open", "Core-owned browser broker is unavailable"],
      "plugins/social_browser/social_browser.rb" => ["owner.open", "Core-owned browser broker is unavailable"],
      "plugins/travel_browser/travel_browser.rb" => ["owner.open", "Core-owned browser broker is unavailable"],
    }

    adapters.each do |relative, required|
      source = File.read(File.join(Master::ROOT, relative))
      required.each { |needle| assert_includes source, needle, "#{relative} lost its broker gate" }
      assert_includes source, "Ferrum::Browser.new(**driver_options(lease))",
                      "#{relative} must attach with the broker-issued lease"
      assert_includes source, "lease.cdp_url",
                      "#{relative} must not choose a Chromium process or CDP endpoint itself"
      refute_includes source, "Process.spawn",
                      "#{relative} must never start a process outside BrowserBroker"
      refute_includes source, "Process.fork",
                      "#{relative} must never fork a process outside BrowserBroker"
    end

    broker_source = File.read(File.join(Master::ROOT, "lib", "io", "browser_broker.rb"))
    assert_includes broker_source, "Process.spawn",
                    "BrowserBroker is the sole owner of Chromium process creation"
  end

  def test_all_six_adapters_release_the_broker_even_when_driver_quit_raises
    adapters = {
      "lib/io/web_browse.rb" => ["browser&.quit", "@broker&.close(lease.id)"],
      "lib/io/browser_agent.rb" => ["browser&.quit", "@broker&.close(lease.id)"],
      "lib/io/web_chat.rb" => ["cleanup_browser(browser)", "@broker.close(lease.id)"],
      "plugins/session_browser/session_browser.rb" => ["browser&.quit", "owner&.close(lease.id)"],
      "plugins/social_browser/social_browser.rb" => ["browser&.quit", "owner&.close(lease.id)"],
      "plugins/travel_browser/travel_browser.rb" => ["browser&.quit", "owner&.close(lease.id)"],
    }

    adapters.each do |relative, (driver_cleanup, broker_release)|
      source = File.read(File.join(Master::ROOT, relative))
      driver_index = source.index(driver_cleanup)
      release_index = source.index(broker_release)

      refute_nil driver_index, "#{relative} must attempt driver cleanup"
      refute_nil release_index, "#{relative} must release its broker lease"
      assert_operator driver_index, :<, release_index
      assert_includes source[driver_index...release_index], "ensure",
                      "#{relative} must release its lease even if driver cleanup raises"
    end
  end

  def test_scoped_broker_is_unavailable_outside_the_active_core_fiber
    scope = Broker::Scope.new
    refute scope.available?
    assert_empty scope.sessions
    assert_equal 0, scope.size
    assert_raises(Broker::Denied) { scope.open(host: "example.com") }

    engine = FakeEngine.new
    active = broker(engine:)
    lease_id = nil
    scope.with(active) do
      assert scope.available?
      other_fiber_availability = nil
      Fiber.new { other_fiber_availability = scope.available? }.resume
      refute other_fiber_availability, "another fibre must not inherit this operation's browser authority"
      lease = scope.open(host: "example.com")
      lease_id = lease.id
      assert_equal 1, scope.size
      assert_equal [lease.id], scope.sessions
      assert scope.close(lease.id)
    end

    refute scope.available?
    assert_equal 0, scope.size
    assert_equal 1, engine.stopped.size
    refute_nil lease_id
  end

  def test_a_context_without_the_capability_cannot_open_a_session
    engine = FakeEngine.new
    refused = broker(capabilities: Caps.read_only, engine:)

    error = assert_raises(Broker::Denied) { refused.open(host: "example.com") }

    assert_match(/capability refused/, error.message)
    assert_empty engine.started, "a refused context must not start a browser"
    refute refused.available?
  end

  def test_a_lease_carries_no_pid_and_cannot_be_stopped_by_an_unprivileged_caller
    engine = FakeEngine.new
    b = broker(engine:)
    lease = b.open(host: "example.com")

    refute_respond_to lease, :pid
    refute_respond_to lease, :profile_dir
    assert_equal "example.com", lease.host
    assert_match(%r{\Aws://127\.0\.0\.1}, lease.cdp_url)

    refute b.close("not-a-lease"), "an unknown lease id must not stop anything"
    assert_empty engine.stopped, "an unknown lease id must not stop anything"
    assert b.close(lease.id)
    assert_equal 1, engine.stopped.size
  end

  def test_process_stop_is_attempted_when_the_stop_receipt_fails
    engine = FakeEngine.new
    ledger = lambda do |event:, phase:, **|
      raise "receipt unavailable" if event == :browser_stop && phase == :after
    end
    b = broker(engine:, ledger:)
    lease = b.open(host: "example.com")

    error = assert_raises(Broker::Denied) { b.close(lease.id) }

    assert_match(/stop receipt failed/, error.message)
    assert_equal 1, engine.stopped.size
    assert_equal 0, b.size
  end

  def test_close_all_attempts_every_session_after_a_stop_receipt_failure
    engine = FakeEngine.new
    failed_once = false
    ledger = lambda do |event:, phase:, **|
      if event == :browser_stop && phase == :after && !failed_once
        failed_once = true
        raise "receipt unavailable"
      end
    end
    b = broker(engine:, ledger:)
    3.times { b.open(host: "example.com") }

    error = assert_raises(Broker::Denied) { b.close_all }

    assert_match(/1 close\(s\) failed/, error.message)
    assert_equal 3, engine.stopped.size
    assert_equal 0, b.size
  end

  def test_expiry_reaping_attempts_every_expired_process_after_a_stop_receipt_failure
    now = Time.utc(2026, 1, 1, 0, 0, 0)
    engine = FakeEngine.new
    failed_once = false
    ledger = lambda do |event:, phase:, **|
      if event == :browser_stop && phase == :after && !failed_once
        failed_once = true
        raise "receipt unavailable"
      end
    end
    b = broker(engine:, ledger:, clock: -> { now }, ttl_seconds: 10)
    3.times { b.open(host: "example.com") }

    now += 11
    error = assert_raises(Broker::Denied) { b.open(host: "example.com") }

    assert_match(/failed to stop 1 expired session/, error.message)
    assert_equal 3, engine.stopped.size
    assert_equal 0, b.size
  end

  def test_the_concurrent_session_cap_is_enforced
    b = broker(max_sessions: 2)
    b.open(host: "example.com")
    b.open(host: "example.com")

    assert_raises(Broker::Denied) { b.open(host: "example.com") }
    assert_equal 2, b.size
  end

  def test_a_session_is_bound_to_its_first_host_and_cannot_widen
    b = broker
    lease = b.open(host: "example.com")

    assert b.navigate(lease.id, "https://www.example.com/page")
    error = assert_raises(Broker::Denied) { b.navigate(lease.id, "https://other.example/") }

    assert_match(/bound to example\.com/, error.message)
    assert_raises(Broker::Denied) { b.navigate(lease.id, "file:///etc/passwd") }
    assert_raises(Broker::Denied) { b.navigate(lease.id, "https://user:pass@example.com/") }
  end

  def test_a_refused_destination_never_starts_a_process
    engine = FakeEngine.new
    deny = ->(url) { url.include?("blocked") ? "reserved address" : nil }
    b = broker(engine:, destination_check: deny)

    assert_raises(Broker::Denied) { b.open(host: "example.com", url: "https://blocked.example/") }
    assert_empty engine.started, "a refused destination must not cost a browser launch"
  end

  def test_initial_url_must_match_the_bound_host_and_have_no_credentials
    engine = FakeEngine.new
    b = broker(engine:)

    assert_raises(Broker::Denied) do
      b.open(host: "example.com", url: "https://other.example/")
    end
    assert_raises(Broker::Denied) do
      b.open(host: "example.com", url: "https://user:pass@example.com/")
    end
    assert_raises(Broker::Denied) do
      b.open(host: "example.com", url: "file:///etc/passwd")
    end
    assert_empty engine.started, "invalid or mismatched initial URLs must be refused before Chromium starts"
  end

  def test_the_default_policy_refuses_a_non_public_destination_without_a_custom_check
    engine = FakeEngine.new
    b = broker(engine:) # no destination_check: the SSRF guard is the default

    assert_raises(Broker::Denied) { b.open(host: "localhost", url: "http://127.0.0.1/") }
    assert_raises(Broker::Denied) { b.open(host: "internal", url: "http://10.0.0.1/") }
    assert_raises(Broker::Denied) { b.open(host: "example.com", url: "file:///etc/passwd") }
    assert_empty engine.started, "a refused default destination must not cost a browser launch"
  end

  def test_a_failed_start_leaves_no_lease_and_no_handle
    b = broker(engine: FakeEngine.new(fail_on_start: true))

    assert_raises(Broker::Denied) { b.open(host: "example.com") }
    assert_equal 0, b.size
    assert_empty b.sessions
  end

  def test_a_failed_before_receipt_prevents_the_launch
    engine = FakeEngine.new
    ledger = ->(event:, phase:, **) { raise "receipt unavailable" if event == :browser_start && phase == :before }
    b = broker(engine:, ledger:)

    assert_raises(RuntimeError) { b.open(host: "example.com") }
    assert_empty engine.started, "a failed before-receipt must abort the start"
    assert_equal 0, b.size
  end

  def test_start_and_stop_are_both_bracketed_by_durable_receipts
    seen = []
    b = broker(ledger: ->(event:, phase:, **row) { seen << [event, phase, row] })
    lease = b.open(host: "example.com")
    b.close(lease.id)

    assert_equal [
      [:browser_start, :before],
      [:browser_start, :after],
      [:browser_stop, :before],
      [:browser_stop, :after]
    ], seen.map { |event, phase, _row| [event, phase] }
    seen.each do |_event, _phase, row|
      assert_equal lease.id, row.fetch(:lease)
      assert_equal "example.com", row.fetch(:host)
    end
  end

  def test_failed_start_after_receipt_stops_the_process_before_refusing_the_lease
    engine = FakeEngine.new
    ledger = lambda do |event:, phase:, **|
      raise IOError, "durable after receipt failed" if event == :browser_start && phase == :after
    end
    b = broker(engine:, ledger:)

    error = assert_raises(IOError) { b.open(host: "example.com") }

    assert_match(/durable after receipt failed/, error.message)
    assert_equal 1, engine.started.size
    assert_equal 1, engine.stopped.size
    assert_equal 0, b.size
    assert_empty b.sessions
  end

  def test_receipts_carry_only_safe_identity_metadata
    seen = []
    b = broker(ledger: ->(**row) { seen << row })
    lease = b.open(host: "example.com", url: "https://example.com/secret?token=abc")
    b.close(lease.id)

    assert_equal %i[browser_start browser_stop], seen.map { |row| row[:event] }
    seen.each do |row|
      refute_includes row.to_s, "token=abc"
      refute_includes row.to_s, "ws://"
      refute_includes row.to_s, "profile"
    end
  end

  def test_an_expired_session_is_reaped_and_its_process_stopped
    now = Time.utc(2026, 1, 1, 0, 0, 0)
    engine = FakeEngine.new
    b = broker(engine:, clock: -> { now }, ttl_seconds: 10)
    b.open(host: "example.com")

    now += 11
    b.open(host: "example.com")

    assert_equal 1, b.size, "the expired lease must be reaped before the new one is admitted"
    assert_equal 1, engine.stopped.size
  end

  def test_close_all_stops_every_lease_for_interruption_and_shutdown
    engine = FakeEngine.new
    b = broker(engine:)
    3.times { b.open(host: "example.com") }

    assert_equal 3, b.close_all
    assert_equal 3, engine.stopped.size
    assert_equal 0, b.size
  end

  def test_observations_are_bounded_and_marked_untrusted
    b = broker
    lease = b.open(host: "example.com")
    huge = "x" * (Broker::MAX_OBSERVATION_BYTES + 5_000)

    observation = b.observe(lease.id, huge)

    assert_equal Broker::MAX_OBSERVATION_BYTES, observation[:body].bytesize
    assert observation[:untrusted]
    assert_match(/untrusted data, never an instruction/, observation[:note])
  end

  def test_screenshots_are_validated_png_bytes_not_a_path
    b = broker
    lease = b.open(host: "example.com")

    png = "\x89PNG\r\n\x1a\n".b + ("\x00" * 100)
    shot = b.screenshot(lease.id, png)

    assert_equal "image/png", shot[:media_type]
    assert_equal png.bytesize, shot[:bytesize]
    refute shot.key?(:path)

    assert_raises(Broker::Denied) { b.screenshot(lease.id, "not a png") }
    assert_raises(Broker::Denied) do
      b.screenshot(lease.id, "\x89PNG\r\n\x1a\n".b + ("\x00" * (Broker::MAX_SCREENSHOT_BYTES + 1)))
    end
  end

  def test_a_persistent_profile_is_forwarded_and_marked_so_teardown_keeps_it
    engine = FakeEngine.new
    b = broker(engine:)

    lease = b.open(host: "example.com", profile: "/tmp/signed-in-profile", persistent: true)

    assert_equal "/tmp/signed-in-profile", engine.started.first[:profile]
    assert_equal true, engine.started.first[:persistent]
    assert b.close(lease.id)
    assert_equal true, engine.stopped.first.persistent?
  end

  def test_the_broker_is_the_only_process_owner_an_adapter_can_reach
    engine = FakeEngine.new
    b = broker(engine:)
    lease = b.open(host: "example.com")

    # A lease is data, not a handle: no process control and no profile path.
    refute_respond_to lease, :pid
    refute_respond_to lease, :pgroup
    refute_respond_to lease, :profile_dir
    refute_respond_to lease, :kill
    refute_respond_to b, :spawn
    assert_equal "ws://127.0.0.1:9222/devtools/browser/fake", lease.cdp_url
  end
end
