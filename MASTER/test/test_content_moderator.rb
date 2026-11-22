# frozen_string_literal: true

require_relative "test_helper"

class TestContentModerator < Minitest::Test
  def setup
    @moderator = Master::Ground::ContentModerator.new
  end

  def test_clean_content_has_no_match
    result = @moderator.analyze(content: { id: 1, text: "Hello there", author_id: 1 })
    assert result.ok?
    assert_equal "NO_MATCH", result.value![:recommendation]
    refute result.value![:action_performed]
  end

  def test_threatening_words_require_human_review
    result = @moderator.analyze(content: { text: "I will hunt you down" })
    assert result.ok?
    assert_equal "REVIEW", result.value![:recommendation]
    assert result.value![:human_authorization_required]
    refute result.value![:action_performed]
  end

  def test_repeat_history_increases_score_without_automatic_action
    first = @moderator.analyze(content: { text: "idiot" }, prior_violations: 0).value!
    repeated = @moderator.analyze(content: { text: "idiot" }, prior_violations: 2).value!
    assert_operator repeated[:weighted_score], :>, first[:weighted_score]
    refute repeated[:action_performed]
  end

  def test_banned_term_is_evidence_not_an_automatic_removal
    result = @moderator.analyze(content: { text: "white supremacy" })
    assert_equal "CRITICAL", result.value![:severity]
    assert_equal "REVIEW", result.value![:recommendation]
  end

  def test_evidence_contains_only_nonzero_signals
    result = @moderator.analyze(content: { text: "idiot" }).value!
    assert_equal({ abusive: 1 }, result[:evidence])
  end
  def test_numeric_string_config_is_normalized_before_analysis
    moderator = Master::Ground::ContentModerator.new(
      config: { review_threshold: "5", repeat_offender_multiplier: "2.0" },
    )
    result = moderator.analyze(content: { text: "idiot" }, prior_violations: 1)
    assert result.ok?, result.message
    assert_equal 16, result.value![:weighted_score]
    assert_equal "REVIEW", result.value![:recommendation]
  end

end
