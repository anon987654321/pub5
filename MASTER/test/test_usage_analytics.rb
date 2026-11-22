# frozen_string_literal: true

require_relative "test_helper"

class TestUsageAnalytics < Minitest::Test
  def setup
    @dir = Dir.mktmpdir("usage-analytics")
    @now = Time.utc(2026, 11, 12, 12)
    @consent = ->(user_id:, purpose:) { user_id == "user-secret" && purpose == Master::Ground::UsageAnalytics::PURPOSE }
    @analytics = Master::Ground::UsageAnalytics.new(root: @dir, consent_check: @consent, clock: -> { @now })
  end

  def teardown
    FileUtils.remove_entry(@dir) if File.directory?(@dir)
  end

  def test_denies_tracking_without_explicit_consent
    analytics = Master::Ground::UsageAnalytics.new(root: @dir, clock: -> { @now })
    result = analytics.record(user_id: "user-secret", feature: "feed", action: "view", platform: "web")
    assert result.err?
    assert_equal :policy, result.category
    refute File.exist?(File.join(@dir, Master::Ground::UsageAnalytics::STORE_NAME))
  end

  def test_records_aggregate_event_without_user_identifier
    result = @analytics.record(
      user_id: "user-secret", feature: "feed", action: "view", platform: "web",
      metadata: { version: "1.2", email: "private@example.test" },
    )
    assert result.ok?
    path = File.join(@dir, Master::Ground::UsageAnalytics::STORE_NAME)
    stored = File.read(path)
    refute_includes stored, "user-secret"
    refute_includes stored, "private@example.test"
    assert_includes stored, '"version":"1.2"'
  end

  def test_report_obeys_both_time_boundaries
    @analytics.record(user_id: "user-secret", feature: "feed", action: "view", platform: "web")
    @now += 38600
    @analytics.record(user_id: "user-secret", feature: "search", action: "submit", platform: "web")
    result = @analytics.report(since: Time.utc(2026, 11, 12, 12), until_at: Time.utc(2026, 11, 12, 13))
    assert result.ok?
    assert_equal 1, result.value![:total_events]
    assert_nil result.value![:distinct_users_by_feature]
  end
end
