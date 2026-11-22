# frozen_string_literal: true

require_relative "test_helper"

class TestSecurityMonitor < Minitest::Test
  def setup
    @now = Time.utc(2026, 11, 12, 12)
    @monitor = Master::Ground::SecurityMonitor.new(
      config: { failed_login_threshold: 5, suspicious_session_threshold: 5, unusual_api_threshold: 100 },
      clock: -> { @now },
    )
  end

  def event(type, **values)
    { type:, at: @now - 1, user_id: values.fetch(:user_id, "user-42"),
      ip: values.fetch(:ip, "203.0.113.7"), country: values[:country],
      user_agent: values[:user_agent], endpoint: values[:endpoint] }
  end

  def test_empty_window_is_not_reported_as_safe
    result = @monitor.analyze(events: [])
    assert result.ok?
    assert_equal 0, result.value![:event_count]
    refute_empty result.value![:not_run]
  end

  def test_failed_login_threshold_is_aggregated_without_identifiers
    events = Array.new(6) { event("FAILED_LOGIN") }
    data = @monitor.analyze(events: events).value!
    assert_equal 6, data[:findings][:failed_logins][:total]
    assert_equal 1, data[:findings][:failed_logins][:suspicious_user_count]
    refute_includes data.to_s, "user-42"
    refute_includes data.to_s, "203.0.113.7"
  end

  def test_rapid_sessions_and_geo_anomaly_are_signals_not_verdicts
    events = [
      event("SESSION_CREATED", country: "NO", user_agent: "A"),
      event("SESSION_CREATED", country: "SE", user_agent: "B"),
      event("SESSION_CREATED", country: "DK", user_agent: "C"),
      event("SESSION_CREATED", country: "US", user_agent: "D"),
      event("SESSION_CREATED", country: "GB", user_agent: "E"),
    ]
    data = @monitor.analyze(events: events).value!
    findings = data[:findings][:suspicious_sessions]
    assert_equal 1, findings[:suspicious_user_count]
    assert_equal 1, findings[:pattern_counts][:geo]
    assert_equal 1, findings[:pattern_counts][:rapid]
  end

  def test_high_volume_api_use_is_counted
    events = Array.new(101) { event("API_CALL", endpoint: "/api/feed") }
    data = @monitor.analyze(events: events).value!
    assert_equal 1, data[:findings][:unusual_api][:high_volume_user_count]
  end

  def test_upper_window_boundary_is_exclusive
    events = [event("FAILED_LOGIN")]
    data = @monitor.analyze(events: events, since: @now, until_at: @now)
    assert data.err?
  end
  def test_numeric_string_config_is_normalized_before_analysis
    monitor = Master::Ground::SecurityMonitor.new(
      config: {
        failed_login_threshold: "5",
        suspicious_session_threshold: "5",
        unusual_api_threshold: "100",
        analysis_window_hours: "24",
      },
      clock: -> { @now },
    )
    events = Array.new(6) { event("FAILED_LOGIN") }
    result = monitor.analyze(events: events)
    assert result.ok?, result.message
    assert_equal 1, result.value![:findings][:failed_logins][:suspicious_user_count]
  end

end
