# frozen_string_literal: true

# The Sonitex wear-pass battery: the analog chain that mutates a mix is the
# part of dilla whose arithmetic is invisible until you feed it a rig, so the
# proof here feeds it directly and counts what changed. Every method a
# capability promotion cites under Studio::AnalogCapabilities must live here.
require_relative "minitest_helper"
require_relative "../dilla/dilla"

class TestDillaWear < Minitest::Test
  def stereo(samples)
    s = Dilla::Stereo.new(samples.length)
    s.l = samples.dup
    s.r = samples.dup
    s
  end

  def flat(n, value)
    stereo(Array.new(n, value))
  end

  def cfg
    {
      "highpass" => 40.0, "lowpass" => 9000.0, "drive" => 1.4,
      "bits" => 12, "wow" => 0.0, "crackle" => 0.3, "hiss" => 0.4,
      "dropout" => 0.0,
    }
  end

  def test_shared_stochastic_walk_is_seeded_bounded_and_nonperiodic
    first = AnalogCore::StochasticWalk.new(
      rate_hz: 0.8, depth: 0.5, rng: Random.new(23), sample_rate: 100
    ).run(5_000)
    repeat = AnalogCore::StochasticWalk.new(
      rate_hz: 0.8, depth: 0.5, rng: Random.new(23), sample_rate: 100
    ).run(5_000)

    assert_equal first, repeat
    assert first.all?(&:finite?)
    assert first.all? { |value| value.abs <= 1.5 }
    assert_operator first.uniq.length, :>, 1_000
    rms = Math.sqrt(first.sum { |value| value * value } / first.length)
    assert_operator rms, :>, 0.35
    assert_operator rms, :<, 0.65
  end

  def test_shared_stochastic_walk_rejects_invalid_domains
    assert_raises(ArgumentError) do
      AnalogCore::StochasticWalk.new(
        rate_hz: 51, depth: 1, rng: Random.new(1), sample_rate: 100
      )
    end
    assert_raises(ArgumentError) do
      AnalogCore::StochasticWalk.new(
        rate_hz: 1, depth: -1, rng: Random.new(1), sample_rate: 100
      )
    end
    zeros = AnalogCore::StochasticWalk.new(
      rate_hz: 0, depth: 1, rng: Random.new(1), sample_rate: 100
    ).run(10)
    assert_equal Array.new(10, 0.0), zeros
  end

  def test_wow_flutter_is_seeded_and_keeps_the_first_sample
    source = Array.new(80_000) { |index| Math.sin(2.0 * Math::PI * 440 * index / Dilla::SAMPLE_RATE) }
    config = cfg.merge("wow" => 0.8, "flutter" => 0.45, "crackle" => 0.0, "hiss" => 0.0)
    first = stereo(source)
    repeat = stereo(source)
    Dilla::Sonitex.wow_flutter!(first, config, Random.new(31))
    Dilla::Sonitex.wow_flutter!(repeat, config, Random.new(31))

    assert_equal first.l, repeat.l
    assert_equal first.r, repeat.r
    assert_in_delta source.first, first.l.first, 1e-12
    refute_equal source, first.l
    assert first.l.all?(&:finite?)
    assert first.r.all?(&:finite?)
  end

  def test_compounded_wear_variation_is_seeded_and_bounded
    first = Dilla::Sonitex.vary(cfg, Random.new(19))
    repeat = Dilla::Sonitex.vary(cfg, Random.new(19))
    refute_equal cfg, first
    assert_equal first, repeat
    assert_operator first.fetch("drive"), :>=, cfg.fetch("drive") * 0.90
    assert_operator first.fetch("drive"), :<=, cfg.fetch("drive") * 1.10
    assert_operator first.fetch("lowpass"), :>=, cfg.fetch("lowpass") * 0.95
    assert_operator first.fetch("lowpass"), :<=, cfg.fetch("lowpass") * 1.05
  end

  # DILLA rig key vinyl_crackle_density: spike density comes from the rig
  # amount, the spikes come from the run's seeded rng, and the same seed must
  # reproduce the same surface — a render the listener could re-run exactly.
  def test_vinyl_crackle_density_is_seeded_and_amount_scales
    base = flat(60_000, 0.0)
    loud = flat(60_000, 0.0)
    Dilla::Sonitex.crackle!(base, 0.1, Random.new(7))
    Dilla::Sonitex.crackle!(loud, 0.6, Random.new(7))

    assert_equal base.l.length, loud.l.length
    same_seed = flat(60_000, 0.0)
    Dilla::Sonitex.crackle!(same_seed, 0.1, Random.new(7))
    assert_equal base.l.map { |v| (v * 1e9).round }, same_seed.l.map { |v| (v * 1e9).round },
                 "the same seed must reproduce the same crackle surface"
    # Spike amplitude is amount * 0.5; a silent bed leaves the rig's own scale.
    assert_operator loud.l.map(&:abs).max, :>, base.l.map(&:abs).max * 5,
                   "the denser rig's spikes must land harder than the quiet rig's"
    assert_operator loud.l.map(&:abs).max, :<=, 0.5, "spikes clamp to the codec range"
  end

  # DILLA rig key tape_transient_softening: one_pass drives each sample
  # through tanh, so a peak that meets the drive is *rounded*, never pinned
  # at the rail the way a hard clipper pins it.
  def test_tape_transient_softening_rounds_the_peaks_instead_of_pinning
    # The drive stage is measured alone: crackle and hiss land after the rail
    # and could push the mix past 1.0 as their own last-stage arithmetic.
    silent = cfg.merge("crackle" => 0.0, "hiss" => 0.0)
    mix = flat(5_000, 2.0)
    Dilla::Sonitex.one_pass!(mix, silent, Random.new(11))

    assert_operator mix.l.max.abs, :<, 1.0,
                   "tanh rounds the driven peak; a hard limiter would pin at exactly 1.0"
    assert_operator mix.l.max.abs, :>, 0.9,
                   "the softened peak still carries the transient's weight"
  end

  # DILLA rig key sp1200_bandwidth: the wear pass band-limits through one-pole
  # filters before it colours anything — highpass strips the DC, lowpass
  # decays the tail.
  def test_the_wear_pass_band_limits_before_it_colours
    dc = flat(4_000, 1.0)
    Dilla::Sonitex.one_pass!(dc, cfg, Random.new(3))
    assert_operator dc.l[-1].abs, :<, 0.05,
                   "the highpass must bleed the held note toward zero"

    impulse = stereo(Array.new(4_000, 0.0))
    impulse.l[0] = impulse.r[0] = 1.0
    Dilla::Sonitex.one_pass!(impulse, cfg, Random.new(3))
    assert_operator impulse.l[1], :>, 0.0
    assert_operator impulse.l[1], :<, impulse.l[0]
    assert_operator impulse.l[200], :<, impulse.l[1] * 0.9,
                   "the lowpass must decay the tail"
  end
end
