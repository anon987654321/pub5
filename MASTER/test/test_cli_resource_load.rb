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

  def test_turn_keeps_process_pressure_when_host_cpu_count_is_unavailable
    resource_load = Master::CLI::Session::ResourceLoad
    snapshot = ->(_argv) { TREE }

    score = resource_load.turn(
      root_pid: 100, snapshot:, load_average: [4.0, 2.0, 1.0], cpu_count: 0
    )

    assert_in_delta resource_load.score(130.0, 11_264), score, 1e-6
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
    assert_nil resource_load.host_score([1.0, 2.0, 3.0], Float::INFINITY)
  end

  def test_spinner_keeps_an_ascii_star_and_clamped_cadence
    session = Master::CLI::Session.allocate
    frames = Master::CLI::Session::SPINNER_FRAMES

    assert_equal ["*", "**", "***", "**"], frames
    assert frames.all? { |frame| frame.match?(/\A\*+\z/) }
    assert_equal 0.18, Master::CLI::Session::TICK_SECONDS
    assert_equal 0.04, Master::CLI::Session::FAST_TICK_SECONDS
    assert_equal 0.18, session.send(:spin_pause, 0.0)
    assert_equal 0.04, session.send(:spin_pause, 1.0)
    assert_equal 0.18, session.send(:spin_pause, -1.0)
    assert_equal 0.04, session.send(:spin_pause, 2.0)
    assert_operator session.send(:spin_pause, 0.9), :<, session.send(:spin_pause, 0.3)
  end

  def test_spinner_hides_the_internal_intake_label
    session = Master::CLI::Session.allocate
    session.define_singleton_method(:spin_suffix) { "" }

    line = session.send(:spin_line, "intake", "*")
    assert_equal %q{* \_}, line
    refute_includes line, "intake"
  end

  def test_spinner_tint_tracks_cpu_load_from_light_to_dark_red
    session = Master::CLI::Session.allocate

    assert_equal "\e[38;2;255;119;119m", session.send(:spinner_tint, 0.0)
    assert_equal "\e[38;2;143;16;16m", session.send(:spinner_tint, 1.0)
    low = session.send(:spinner_tint, 0.25)
    high = session.send(:spinner_tint, 0.75)
    assert_equal "\e[38;2;227;93;93m", low
    assert_equal "\e[38;2;171;42;42m", high
    painted = session.send(:spin_tinted, "** working", 1.0)
    assert_match(/\A\e\[38;2;143;16;16m\*\*\e\[0m working\z/, painted)
    refute_includes painted, "255;255;255"
  end

  def test_spinner_respects_no_color_and_dumb_terminals
    session = Master::CLI::Session.allocate
    no_color = ENV["NO_COLOR"]
    term = ENV["TERM"]

    ENV["NO_COLOR"] = "1"
    assert_nil session.send(:spinner_tint, 0.5)
    ENV.delete("NO_COLOR")
    ENV["TERM"] = "dumb"
    assert_nil session.send(:spinner_tint, 0.5)
  ensure
    no_color.nil? ? ENV.delete("NO_COLOR") : ENV["NO_COLOR"] = no_color
    term.nil? ? ENV.delete("TERM") : ENV["TERM"] = term
  end

  def test_spinner_uses_normalized_host_cpu_load_average
    resource_load = Master::CLI::Session::ResourceLoad
    resource_load.stub(:system_load_average, [4.0, 2.0, 1.0]) do
      resource_load.stub(:logical_cpu_count, 4) do
        assert_in_delta 0.775, resource_load.cpu_load, 1e-6
      end
    end
  end

  def test_spinner_stays_uncoloured_when_cpu_load_is_unavailable
    session = Master::CLI::Session.allocate

    Master::CLI::Session::ResourceLoad.stub(:cpu_load, nil) do
      intensity, = session.send(:probe_intensity, nil, 0.0)
      assert_nil intensity
      assert_equal "** working", session.send(:spin_tinted, "** working", intensity)
      assert_equal Master::CLI::Session::TICK_SECONDS, session.send(:spin_pause, intensity)
    end
  end

  def test_spinner_probe_uses_cpu_load_not_process_pressure
    session = Master::CLI::Session.allocate

    Master::CLI::Session::ResourceLoad.stub(:cpu_load, 0.625) do
      intensity, next_probe = session.send(:probe_intensity, 0.0, 0.0)
      assert_equal 0.625, intensity
      assert_operator next_probe, :>, 0.0
    end
  end
end
