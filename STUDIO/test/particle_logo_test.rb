# frozen_string_literal: true

require "json"
require "digest"
require_relative "minitest_helper"
require_relative "../particle_logo"

# The plur1bus particle mark is a fixed function of its inputs, so these tests
# pin determinism, the gather-to-hold motion, the loop seam, the signal budget
# and the tone. The raster (rsvg-convert) and the demo compose (ffmpeg) are
# external tools; the mask integration is skipped where they are absent, and
# the field logic is exercised against a stub source so it never needs them.
class TestParticleLogo < Minitest::Test
  AMBER = File.expand_path("../../RAILS/amber/__logo/plates/reference-original.svg", __dir__)

  # A source whose ink is a solid centred band: the field logic is the subject,
  # not rsvg.
  class StubSource
    attr_reader :view_box, :name

    def initialize(width: 400, height: 200, name: "stub")
      @view_box = [0.0, 0.0, width.to_f, height.to_f]
      @name = name
    end

    def mask(width:, height:)
      points = []
      (height / 4...3 * height / 4).each do |y|
        (width / 4...3 * width / 4).each { |x| points << [x, y] }
      end
      points
    end
  end

  def field(count: 120, seed: 5, tone: :dark)
    Studio::ParticleLogo::Field.new(StubSource.new, width: 400, height: 200,
                                    count: count, seed: seed, tone: tone)
  end

  def test_fit_scales_width_and_keeps_aspect
    assert_equal [420, 210], Studio::ParticleLogo.fit(420, [0.0, 0.0, 1000.0, 500.0])
    assert_equal [210, 210], Studio::ParticleLogo.fit(210, [0.0, 0.0, 1.0, 1.0])
    assert_raises(ArgumentError) { Studio::ParticleLogo.fit(0, [0.0, 0.0, 1.0, 1.0]) }
  end

  def test_rng_is_a_deterministic_stream
    a = Studio::ParticleLogo::Rng.new(9)
    b = Studio::ParticleLogo::Rng.new(9)
    assert_equal Array.new(5) { a.rand }, Array.new(5) { b.rand }
    refute_equal Studio::ParticleLogo::Rng.new(9).rand, Studio::ParticleLogo::Rng.new(10).rand
  end

  def test_homes_are_deterministic_for_one_seed
    assert_equal field.homes, field.homes
    refute_equal field(seed: 5).homes, field(seed: 6).homes
  end

  def test_field_samples_the_requested_carrier_count
    assert_equal 120, field(count: 120).size
  end

  def test_frame_is_a_fixed_function_of_phase
    f = field
    assert_equal f.frame(0.25), f.frame(0.25)
    refute_equal f.frame(0.25), f.frame(0.75)
  end

  def test_gather_moves_then_holds_and_loops
    f = field
    assert_equal f.frame(0.0), f.frame(1.0), "the film must loop at the seam"
    # gather (0.1) differs from settled (0.6): carriers are still arriving.
    refute_equal f.frame(0.1), f.frame(0.6)
    # two settled frames a full loop apart are identical.
    assert_equal f.frame(0.6), f.frame(1.6)
  end

  def test_signal_stays_under_the_highlight_budget
    json = JSON.parse(Studio::ParticleLogo.homes_json(StubSource.new, size: 400, count: 200, seed: 1))
    lit = json.fetch("homes").count { |_, _, _, signal| signal == 1 }
    budget = (200 * Studio::ParticleLogo::MAX_SIGNAL_FRACTION).round
    assert_operator lit, :<=, [budget, 1].max
    assert_operator lit, :>=, 1
  end

  def test_homes_json_declares_the_field
    json = JSON.parse(Studio::ParticleLogo.homes_json(StubSource.new, size: 400, count: 50, seed: 3))
    assert_equal 400, json.fetch("width")
    assert_equal 200, json.fetch("height")
    assert_equal Studio::ParticleLogo::SIGNAL, json.fetch("signal")
    assert_equal 50, json.fetch("homes").length
  end

  def test_light_tone_draws_light_carriers
    svg = field(tone: :light).frame(0.7)
    refute_includes svg, "#0F0F0F" # the dark ink never appears in the light tone
    assert_match(/#[CDEF][0-9A-F]{5}/, svg)
  end

  def test_unknown_tone_is_rejected
    assert_raises(ArgumentError) do
      Studio::ParticleLogo::Field.new(StubSource.new, width: 10, height: 10, count: 4, tone: :neon)
    end
  end

  def test_amber_reference_parses_to_glyph_geometry
    source = Studio::ParticleLogo::Source.from_file(AMBER, name: "amber")
    assert_equal [0.0, 0.0, 1000.0, 500.0], source.view_box
    assert_equal "amber", source.name
  end

  def test_render_frames_and_mask_need_rsvg
    skip "rsvg-convert is not installed" if `which rsvg-convert`.strip.empty?

    source = Studio::ParticleLogo::Source.from_file(AMBER, name: "amber")
    field = Studio::ParticleLogo::Field.new(source, width: 320, height: 160, count: 300, seed: 2)
    assert_operator field.size, :>, 0
    Dir.mktmpdir do |dir|
      frames = Studio::ParticleLogo.render_frames(source, out_dir: dir, frames: 3, size: 320, count: 300, seed: 2)
      assert_equal 3, frames.length
      frames.each { |path| assert File.file?(path), "missing frame #{path}" }
      assert_equal frames[0], frames[0] # stable identity of the returned list
      assert_equal Digest::SHA256.file(frames[0]).hexdigest, Digest::SHA256.file(frames[0]).hexdigest
    end
  end
end
