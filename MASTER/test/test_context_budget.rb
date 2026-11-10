# frozen_string_literal: true

require_relative "test_helper"

class TestContextBudget < Minitest::Test
  BUDGET = Master::CLI::Routing::ModelRouter::ContextBudget

  def test_estimate_counts_chars_over_the_shared_constant
    assert_equal 10, BUDGET.token_count({ role: "user", content: "x" * 40 })
    assert_equal 1, BUDGET.token_count({ role: "user", content: "hi" })
    assert_equal 1, BUDGET.token_count({ role: "user", content: "" })
  end

  def test_fit_passes_history_through_under_the_budget
    messages = [{ role: "system", content: "s" * 100 }, { role: "user", content: "u" * 100 }]
    assert_same messages, BUDGET.fit(messages, 8_000)
    # No window, no budget: a lane whose window is unknown is not compacted.
    assert_same messages, BUDGET.fit(messages, 0)
    assert_same messages, BUDGET.fit(messages, nil)
  end

  def test_fit_drops_oldest_turns_first_and_keeps_system_rows
    system = { role: "system", content: "s" * 400 }
    history = 3_000.times.map { { role: "user", content: "x" * 40 } }
    fitted = BUDGET.fit([system] + history, 8_000)

    assert_equal system, fitted.first
    assert_equal history.last, fitted.last
    assert_operator BUDGET.estimate(fitted), :<=, (8_000 * BUDGET::SAFE_MARGIN).to_i
    assert_operator fitted.size, :<, history.size + 1
  end

  def test_strict_mode_raises_overflow_instead_of_compacting
    messages = 100.times.map { { role: "user", content: "x" * 400 } }
    error = assert_raises(BUDGET::Overflow) { BUDGET.fit(messages, 1_000, mode: :strict) }
    assert_match(/tokens/, error.message)
  end
end
