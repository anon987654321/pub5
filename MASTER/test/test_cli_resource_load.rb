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

  def test_turn_blends_weighted_host_load_with_process_tree_pressure
    resource_load = Master::CLI::Session::ResourceLoad
    snapshot = ->(_argv) { TREE }
    process_pressure = resource_load.score(130.0, 11_264)
    host_pressure = resource_load.host_score([4.0, 2.0, 1.0], 4)

    score = resource_load.turn(
      root_pid: 100, snapshot:, load_average: [4.0, 2.0, 1.0], cpu_count: 4
    )

    expected = process_pressure * resource_load::PROCESS_WEIGHT +
      host_pressure * resource_load::HOST_WEIGHT
    assert_in_delta expected, score, 1e-6
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

  def test_host_load_uses_sixty_thirty_ten_weights_and_cpu_normalization
    resource_load = Master::CLI::Session::ResourceLoad

    assert_in_delta 0.775, resource_load.host_score([4.0, 2.0, 1.0], 4), 1e-6
    assert_equal 1.0, resource_load.host_score([16.0, 16.0, 16.0], 4)
    assert_nil resource_load.host_score([1.0, 2.0], 4)
    assert_nil resource_load.host_score([1.0, Float::INFINITY, 2.0], 4)
  end

  def test_spinner_has_sixteen_portable_ascii_keyframes_and_clamped_cadence
    session = Master::CLI::Session.allocate
    frames = Master::CLI::Session::SPINNER_FRAMES

    assert_equal 16, frames.length
    assert frames.all? { |frame| frame.match?(/\\A[ -~]\\z/) }
    assert_equal 0.18, Master::CLI::Session::TICK_SECONDS
    assert_equal 0.04, Master::CLI::Session::FAST_TICK_SECONDS
    assert_equal 0.18, session.send(:spin_pause, 0.0)
    assert_equal 0.04, session.send(:spin_pause, 1.0)
    assert_equal 0.18, session.send(:spin_pause, -1.0)
    assert_equal 0.04, session.send(:spin_pause, 2.0)
    assert_operator session.send(:spin_pause, 0.9), :<, session.send(:spin_pause, 0.3)
  end

  def test_spinner_tint_ramps_amber_to_red_above_its_threshold
    session = Master::CLI::Session.allocate

    refute_includes session.send(:spinner_tint, 0.2).inspect, "\\e[38;2"
    refute_nil session.send(:spinner_tint, 0.4)
    greens = [0.5, 1.0].map { |i| Integer(session.send(:spinner_tint, i)[/\\e\\[38;2;255;(\\d+);30m/, 1]) }
    assert_operator greens.first, :>, greens.last
    assert_equal 40, greens.last
  end

  def test_spinner_leading_glyph_turns_white_hot_at_critical_intensity
    session = Master::CLI::Session.allocate

    painted = session.send(:spin_tinted, "x working", 0.99)

    assert_match(/\\A\\e\\[1;38;2;255;255;255mx\\e\\[0m/, painted)
    assert_includes painted, "\\e[38;2;"
  end
end
