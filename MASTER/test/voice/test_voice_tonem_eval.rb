# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../lib/voice/benchmark"

class TestVoiceTonemEval < Minitest::Test
  Benchmark = Master::Voice::Benchmark

  # Doubles for the aubionotes subprocess: no test spawns audio or reaches
  # the network. capture3 answers [out, err, status] in popen order.
  StubStatus = Struct.new(:ok) do
    def success? = ok
  end

  def test_pitch_track_parses_aubionotes_lines
    out = "0.10\t 220.5\n0.20\t 224.1\n0.30\t 218.9\n0.40\t 600.0\njunk line\n"
    stub_executable(true)
    Master::Io::Exec.stub(:capture3, ->(*_cmd, **_opts) { [out, "", StubStatus.new(true)] }) do
      track = Benchmark.pitch_track("solen.wav")

      assert_equal 3, track.length
      assert_in_delta 0.10, track[0][:t], 0.0001
      assert_in_delta 220.5, track[0][:hz], 0.0001
      assert_in_delta 224.1, track[1][:hz], 0.0001
      # The 600 Hz line is outside the voiced gate and is dropped.
      assert_operator track.map { |p| p[:hz] }.max, :<=, 500
    end
  end

  def test_pitch_track_fails_closed
    stub_executable(false)
    Master::Io::Exec.stub(:capture3, ->(*_cmd, **_opts) { flunk "a missing aubio must not reach Exec" }) do
      assert_nil Benchmark.pitch_track("solen.wav")
    end

    stub_executable(true)
    Master::Io::Exec.stub(:capture3, ->(*_cmd, **_opts) { ["", "", StubStatus.new(false)] }) do
      assert_nil Benchmark.pitch_track("solen.wav")
    end

    Master::Io::Exec.stub(:capture3, ->(*_cmd, **_opts) { ["0.10\t 220.5\n", "", StubStatus.new(true)] }) do
      # A single point is returned as-is; it simply cannot produce a verdict.
      single = Benchmark.pitch_track("solen.wav")
      assert_equal 1, single.length
    end
  end

  def test_aubio_pitch_summary_keeps_its_shape
    out = "0.10\t 220.5\n0.20\t 224.1\n0.30\t 218.9\n"
    stub_executable(true)
    Master::Io::Exec.stub(:capture3, ->(*_cmd, **_opts) { [out, "", StubStatus.new(true)] }) do
      summary = Benchmark.aubio_pitch("solen.wav")

      assert_equal 218.9, summary[:min_hz]
      assert_equal 224.1, summary[:max_hz]
      assert_in_delta 221.2, summary[:mean_hz], 0.05
      assert_in_delta 5.2, summary[:range_hz], 0.05
    end
  end

  def test_classify_peak_timing_places_the_peak_in_the_voiced_span
    assert_equal :early, Benchmark.classify_peak_timing(track_with_peak_at(0.25))
    assert_equal :mid, Benchmark.classify_peak_timing(track_with_peak_at(0.50))
    assert_equal :late, Benchmark.classify_peak_timing(track_with_peak_at(0.80))
    # Not enough points, or a zero span, answers nil.
    assert_nil Benchmark.classify_peak_timing([{ t: 0.1, hz: 220.0 }])
    assert_nil Benchmark.classify_peak_timing([{ t: 0.1, hz: 220.0 }, { t: 0.1, hz: 221.0 }])
    assert_nil Benchmark.classify_peak_timing([])
  end

  def test_classify_direction_reads_the_first_half_slope
    rising = [{ t: 0.0, hz: 200.0 }, { t: 0.5, hz: 250.0 }, { t: 1.0, hz: 300.0 }]
    falling = [{ t: 0.0, hz: 300.0 }, { t: 0.5, hz: 250.0 }, { t: 1.0, hz: 200.0 }]
    level = [{ t: 0.0, hz: 200.0 }, { t: 0.5, hz: 202.0 }, { t: 1.0, hz: 201.0 }]

    assert_equal :rising, Benchmark.classify_direction(rising)
    assert_equal :falling, Benchmark.classify_direction(falling)
    assert_equal :level, Benchmark.classify_direction(level)
    assert_nil Benchmark.classify_direction([{ t: 0.0, hz: 200.0 }])
  end

  def test_least_squares_slope_is_exact_and_degenerates_to_nil
    two_points = [{ t: 0.0, hz: 200.0 }, { t: 1.0, hz: 260.0 }]
    assert_in_delta 60.0, Benchmark.least_squares_slope(two_points), 0.0001

    same_time = [{ t: 0.5, hz: 200.0 }, { t: 0.5, hz: 260.0 }]
    assert_nil Benchmark.least_squares_slope(same_time)
  end

  def test_tonem_target_reads_the_evaluation_fixtures
    bergen = Benchmark.tonem_target("bergen")

    assert_equal :early, bergen[:peak_timing]
    assert_equal :falling, bergen[:direction]
    assert_equal "bergen", bergen[:accent]

    oslo = Benchmark.tonem_target("oslo_standard")

    assert_equal :low_or_rising, oslo[:peak_timing]
    assert_equal :rising_or_level, oslo[:direction]
    assert_nil Benchmark.tonem_target("trondersk")
  end

  def test_tonem_verdict_passes_a_bergen_tonem1_realisation
    bergen = Benchmark.tonem_target("bergen")

    verdict = Benchmark.tonem_verdict(track_with_peak_at(0.25, slope: -80.0), bergen)

    assert_equal :early, verdict[:measured][:peak_timing_class]
    assert_equal :falling, verdict[:measured][:direction]
    assert_equal 1.0, verdict[:score]
    assert verdict[:pass]
  end

  def test_tonem_verdict_fails_the_eastern_low_start_for_bergen
    bergen = Benchmark.tonem_target("bergen")

    # Late peak with a rising onset: the eastern realisation.
    verdict = Benchmark.tonem_verdict(track_with_peak_at(0.80, slope: 80.0), bergen)

    assert_equal 0.0, verdict[:score]
    refute verdict[:pass]
  end

  def test_tonem_verdict_partial_credits_do_not_pass_without_a_direction
    bergen = Benchmark.tonem_target("bergen")

    # Early peak but a level first half: (1.0 + 0.3) / 2 passes, but the
    # mid-peak level variant must not.
    level = [{ t: 0.0, hz: 220.0 }, { t: 0.5, hz: 221.0 }, { t: 1.0, hz: 221.0 }]
    assert Benchmark.tonem_verdict(track_with_peak_at(0.25, slope: 4.0), bergen)[:pass]
    refute Benchmark.tonem_verdict(level, bergen)[:pass]
  end

  def test_tonem_verdict_scores_the_oslo_reference
    oslo = Benchmark.tonem_target("oslo_standard")

    # Eastern tonem-1: late peak, rising or level onset.
    verdict = Benchmark.tonem_verdict(track_with_peak_at(0.80, slope: 80.0), oslo)

    assert_equal 1.0, verdict[:score]
    assert verdict[:pass]

    # The western early high fall is the eastern anti-target.
    refute Benchmark.tonem_verdict(track_with_peak_at(0.25, slope: -80.0), oslo)[:pass]
  end

  def test_tonem_verdict_answers_nil_when_nothing_is_measurable
    bergen = Benchmark.tonem_target("bergen")

    assert_nil Benchmark.tonem_verdict([{ t: 0.1, hz: 220.0 }], bergen)
    assert_nil Benchmark.tonem_verdict([{ t: 0.1, hz: 220.0 }, { t: 0.1, hz: 221.0 }], bergen)
  end

  def test_tonem_eval_fails_closed_without_aubio
    stub_executable(false)
    Master::Io::Exec.stub(:capture3, ->(*_cmd, **_opts) { flunk "no aubio, no subprocess" }) do
      assert_nil Benchmark.tonem_eval("solen.wav", accent: "bergen")
    end
  end

  def test_tonem_eval_answers_nil_for_an_unknown_accent
    stub_executable(true)
    Master::Io::Exec.stub(:capture3, ->(*_cmd, **_opts) { flunk "an unknown accent must not reach Exec" }) do
      assert_nil Benchmark.tonem_eval("solen.wav", accent: "trondersk")
    end
  end

  def test_tonem_eval_returns_the_full_verdict
    out = "0.10\t 240.0\n0.20\t 232.0\n0.30\t 224.0\n0.40\t 220.0\n0.50\t 218.0\n"
    stub_executable(true)
    Master::Io::Exec.stub(:capture3, ->(*_cmd, **_opts) { [out, "", StubStatus.new(true)] }) do
      verdict = Benchmark.tonem_eval("solen.wav", accent: "bergen")

      assert_equal "solen.wav", verdict[:path]
      assert_equal "bergen", verdict[:accent]
      assert verdict[:available]
      assert verdict[:pass]
      assert_equal :early, verdict[:measured][:peak_timing_class]
      assert_equal :falling, verdict[:measured][:direction]
    end
  end

  private

  def stub_executable(ok)
    Benchmark.stub(:executable?, ok)
  end

  # A synthetic voiced span from t=0 to t=1 on a 0.05 grid whose peak sits
  # at rel_position and whose first half walks at slope Hz/s. The grid is
  # fine enough that 0.25, 0.50 and 0.80 all land exactly on a point.
  def track_with_peak_at(rel_position, slope: 0.0)
    base = 220.0
    points = []
    0.upto(20).each do |i|
      t = i / 20.0
      hz = if t <= 0.5
             base + slope * t
           else
             base + slope * 0.5
           end
      hz += 40.0 if (t - rel_position).abs < 1e-9
      points << { t: t, hz: hz.round(2) }
    end
    points
  end
end
