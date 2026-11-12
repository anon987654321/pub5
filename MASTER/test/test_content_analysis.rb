# frozen_string_literal: true

require_relative "test_helper"

class TestContentAnalysis < Minitest::Test
  Analyzer = Master::Ground::ContentAnalysis

  def test_detects_threat_words_as_counts_not_verdicts
    result = Analyzer.scan("I will stalk you and find you")
    assert_equal 2, result[:harassment]
    assert_equal "HIGH", Analyzer.severity(result)
  end

  def test_detects_scam_language
    result = Analyzer.scan("You have won. Send money to claim your prize.")
    assert_operator result[:scam], :>=, 1
    assert_equal "CRITICAL", Analyzer.severity(result)
  end

  def test_clean_content_has_zero_counts
    assert Analyzer.scan("Hello, nice to meet you").values.all?(&:zero?)
  end

  def test_counts_are_frozen_and_complete
    result = Analyzer.scan("idiot")
    assert result.frozen?
    assert_equal Analyzer::KEYS.sort, result.keys.sort
  end

  def test_score_is_deterministic
    assert_equal 25, Analyzer.score(Analyzer.scan("I will stalk you"))
  end
end
