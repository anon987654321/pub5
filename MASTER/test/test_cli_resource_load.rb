# frozen_string_literal: true

require_relative "test_helper"

class TestCliResourceLoad < Minitest::Test
  TREE = <<~PS.freeze
      100     1  10.0  1024
      105   100  90.0  2048
      106   100   0.0     0
      107   106  30.0  8192
      109     1  99.0  2048
    junk  line   1.0     1.0
  PS

  def test_turn_scores_only_the_session_tree
    snapshot = ->(_argv) { TREE }

    score = Master::CLI::Session::ResourceLoad.turn(root_pid: 100, snapshot:)

    # 1024 + 2048 + 0 + 8192 resident under the session pid, not pid 109.
    rss_kb = 11_264
    assert_in_delta 0.6 + 0.4 * (rss_kb / Master::CLI::Session::ResourceLoad::MEMORY_CAP_KB.to_f), score, 1e-6
  end

  def test_turn_without_the_session_row_scores_zero
    snapshot = ->(_argv) { TREE }

    assert_equal 0.0, Master::CLI::Session::ResourceLoad.turn(root_pid: 999, snapshot:)
  end

  def test_score_saturates_at_one_core_and_the_memory_cap
    score = Master::CLI::Session::ResourceLoad

    assert_equal 0.0, score.score(0, 0)
    assert_operator score.score(60, 0), :>, score.score(30, 0)
    assert_equal 1.0, score.score(120.0, Master::CLI::Session::ResourceLoad::MEMORY_CAP_KB)
  end

  def test_spinner_spins_faster_and_redder_with_intensity
    session = Master::CLI::Session.allocate

    assert_equal Master::CLI::Session::TICK_SECONDS, session.send(:spin_pause, 0.0)
    assert_equal Master::CLI::Session::FAST_TICK_SECONDS, session.send(:spin_pause, 1.0)
    assert_operator session.send(:spin_pause, 0.9), :<, session.send(:spin_pause, 0.3)
    assert_equal Master::CLI::Session::SPINNER_FRAMES, ["|", "/", "-", "\\"]
  end

  def test_spinner_tint_ramps_amber_to_red_above_its_threshold
    session = Master::CLI::Session.allocate

    refute_includes session.send(:spinner_tint, 0.2).inspect, "\e[38;2"
    refute_nil session.send(:spinner_tint, 0.4)
    greens = [0.5, 1.0].map { |i| Integer(session.send(:spinner_tint, i)[/\e\[38;2;255;(\d+);30m/, 1]) }
    assert_operator greens.first, :>, greens.last
    assert_equal 40, greens.last
  end
end
