# frozen_string_literal: true

require_relative "test_helper"

class TestUserBehaviorAnalyzer < Minitest::Test
  def setup
    @dir = Dir.mktmpdir("user-behavior")
    @now = Time.utc(2026, 11, 12, 12)
  end

  def teardown
    FileUtils.remove_entry(@dir) if File.directory?(@dir)
  end

  def messages(*texts)
    texts.map { |text| { text:, at: @now } }
  end

  def test_clean_messages_are_low_risk_and_tracking_is_disabled_by_default
    analyzer = Master::Ground::UserBehaviorAnalyzer.new(root: @dir, clock: -> { @now })
    result = analyzer.analyze(messages: messages("Hello", "Nice to meet you"), platform: "web", user_id: "secret-user")
    assert result.ok?
    assert_equal "LOW", result.value![:risk_level]
    assert_equal "NORMAL", result.value![:recommendation]
    assert_includes result.value![:not_run].join, "disabled by default"
    refute File.exist?(File.join(@dir, Master::Ground::UserBehaviorAnalyzer::TRACKER_NAME))
  end

  def test_threat_signals_raise_review_risk_but_never_auto_ban
    analyzer = Master::Ground::UserBehaviorAnalyzer.new(root: @dir, clock: -> { @now })
    result = analyzer.analyze(
      messages: messages("I will stalk you", "You can't hide, I will find you", "I am watching"),
      platform: "web", user_id: "secret-user",
    )
    assert result.ok?
    assert_operator result.value![:score], :>, 20
    assert_equal "REVIEW", result.value![:recommendation]
    refute result.value!.key?(:user_id)
    refute result.value!.key?(:AUTO_BAN)
  end

  def test_cross_platform_history_requires_explicit_consent_and_a_hmac_key
    analyzer = Master::Ground::UserBehaviorAnalyzer.new(
      root: @dir, config: { cross_platform_tracking: true },
      consent_check: ->(**) { false }, identity_key: "k" * 32, clock: -> { @now },
    )
    result = analyzer.analyze(messages: messages("Hello"), platform: "web", user_id: "raw-id-123")
    assert result.ok?
    assert_includes result.value![:not_run].join, "consent"
    refute File.exist?(File.join(@dir, Master::Ground::UserBehaviorAnalyzer::TRACKER_NAME))
  end

  def test_consented_cross_platform_history_is_pseudonymous
    analyzer = Master::Ground::UserBehaviorAnalyzer.new(
      root: @dir, config: { cross_platform_tracking: true },
      consent_check: ->(user_id:, purpose:) { user_id == "raw-id-123" && purpose == Master::Ground::UserBehaviorAnalyzer::PURPOSE },
      identity_key: "k" * 32, clock: -> { @now },
    )
    %w[web mobile].each do |platform|
      assert analyzer.analyze(messages: messages("I will stalk you"), platform:, user_id: "raw-id-123").ok?
    end
    result = analyzer.aggregate(user_id: "raw-id-123")
    assert result.ok?
    assert_equal %w[mobile web], result.value![:platforms]
    content = File.read(File.join(@dir, Master::Ground::UserBehaviorAnalyzer::TRACKER_NAME))
    refute_includes content, "raw-id-123"
    refute_includes content, "I will stalk you"
  end

  def test_forget_removes_pseudonymous_history
    analyzer = Master::Ground::UserBehaviorAnalyzer.new(
      root: @dir, config: { cross_platform_tracking: true },
      consent_check: ->(**) { true }, identity_key: "k" * 32, clock: -> { @now },
    )
    analyzer.analyze(messages: messages("Hello"), platform: "web", user_id: "raw-id")
    assert analyzer.forget(user_id: "raw-id").ok?
    assert analyzer.aggregate(user_id: "raw-id").err?
  end

  def test_empty_messages_is_validation_error
    analyzer = Master::Ground::UserBehaviorAnalyzer.new(root: @dir, clock: -> { @now })
    result = analyzer.analyze(messages: [], platform: "web", user_id: "1")
    assert result.err?
    assert_equal :validation, result.category
  end
end
