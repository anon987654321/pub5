# frozen_string_literal: true

require_relative "minitest_helper"
require "bigdecimal"

begin
  require_relative "../../lora/spend"
rescue LoadError => error
  warn "skipping spend envelope tests: #{error.message}"
  return
end

# Spend visibility is a ratchet only if the envelope logic is pinned: warning
# at 80%, EXCEEDED past the envelope, and an honest NOT_CONFIGURED while the
# operator has not chosen a number.
class TestStudioLoraSpend < Minitest::Test
  Spend = Studio::Lora::Spend

  def rows(*costs)
    costs.map { |cost| { "month" => "2026-11", "cost_usd" => cost } }
  end

  def test_unconfigured_envelope_reports_not_configured_but_still_sums
    summary = Spend.summarize(rows(BigDecimal("1.5"), BigDecimal("2.5")), month: "2026-11", envelope: nil)
    assert_equal "NOT_CONFIGURED", summary.fetch("state")
    assert_equal "4.0", summary.fetch("total_usd")
    assert_equal 2, summary.fetch("priced_receipts")
  end

  def test_within_envelope_below_the_warning_line
    summary = Spend.summarize(rows(BigDecimal("7.9")), month: "2026-11", envelope: BigDecimal("10"))
    assert_equal "WITHIN_ENVELOPE", summary.fetch("state")
  end

  def test_warning_at_eighty_percent
    summary = Spend.summarize(rows(BigDecimal("8.0")), month: "2026-11", envelope: BigDecimal("10"))
    assert_equal "WARNING", summary.fetch("state")
  end

  def test_exceeded_past_the_envelope
    summary = Spend.summarize(rows(BigDecimal("10.01")), month: "2026-11", envelope: BigDecimal("10"))
    assert_equal "EXCEEDED", summary.fetch("state")
  end

  def test_unpriced_receipts_are_counted_not_guessed
    summary = Spend.summarize(rows(BigDecimal("1.0"), nil), month: "2026-11", envelope: BigDecimal("10"))
    assert_equal 1, summary.fetch("unpriced_receipts")
    assert_equal "1.0", summary.fetch("total_usd")
  end

  def test_other_months_do_not_leak_in
    summary = Spend.summarize(rows(BigDecimal("100")), month: "2026-12", envelope: BigDecimal("10"))
    assert_equal "WITHIN_ENVELOPE", summary.fetch("state")
    assert_equal "0.0", summary.fetch("total_usd")
  end
end
