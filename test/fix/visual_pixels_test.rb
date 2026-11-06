# frozen_string_literal: true

require_relative "fix_helper"
require_relative "../../master/fix/visual/lane"

# Moved from pub4 MASTER/test/test_pixel_match.rb (5745846704),
# test_capture_engine.rb's still-shot tests (da2fb285e8),
# test_visual_surface_cap.rb (28a48c6e7d, cf0d9831e1) and
# test_state_matrix.rb (1e939c7f8b).
class FixVisualPixelsTest < Minitest::Test
  V = Fix::Visual
  WHITE = [255, 255, 255, 255].freeze
  BLACK = [0, 0, 0, 255].freeze
  GREY = [128, 128, 128, 255].freeze

  def png(width, height)
    V::Png.encode(width, height, (0...(width * height)).flat_map { |pos| yield(pos % width, pos / width) }.pack("C*"))
  end

  def block(soft:) = png(20, 20) { |col, _| col < 9 ? BLACK : (col == 9 ? (soft ? GREY : BLACK) : WHITE) }

  def test_a_shade_below_the_threshold_is_not_change
    result = V::PixelMatch.compare(png(20, 20) { WHITE }, png(20, 20) { |c, _| c.even? ? [252, 252, 252, 255] : WHITE })
    assert_equal [0, []], result.values_at(:pixel_diff_count, :regions)
  end

  def test_an_edge_resampled_by_one_pixel_is_anti_aliasing_not_change
    result = V::PixelMatch.compare(block(soft: false), block(soft: true))
    assert_equal [0, 20], result.values_at(:pixel_diff_count, :aliased)
  end

  def test_two_separate_changes_come_back_as_two_boxes_and_a_diff_image
    changed = png(64, 64) { |c, r| (c < 4 && r < 4) || (c > 50 && r > 50) ? BLACK : WHITE }
    result = V::PixelMatch.compare(png(64, 64) { WHITE }, changed)

    assert_equal 16 + (13 * 13), result[:pixel_diff_count]
    assert_equal [{ x: 0, y: 0, w: 16, h: 16 }, { x: 48, y: 48, w: 16, h: 16 }], result[:regions]
    assert_equal [64, 64], V::PixelMatch.read(result[:diff_png]).size
  end

  def test_a_crop_is_the_box_enlarged_four_times
    cropped = V::PixelMatch.read(V::PixelMatch.crop(png(32, 32) { |c, _| c < 16 ? BLACK : WHITE }, { x: 12, y: 12, w: 8, h: 8 }, pad: 0))

    assert_equal [32, 32], cropped.size
    assert_equal [V::PixelMatch.pack(BLACK), V::PixelMatch.pack(WHITE)], cropped.pixels.values_at(15, 16)
  end

  def test_a_size_change_is_a_mismatch_not_a_count
    assert_equal :dimension_mismatch, V::PixelMatch.compare(png(4, 4) { WHITE }, png(4, 5) { WHITE })[:status]
  end

  def test_a_shot_is_retaken_until_two_agree_and_a_restless_page_is_unstable
    shots = %w[a b b]
    assert_equal({ png: "b", attempts: 3, stable: true }, V::Still.settle(-> { shots.shift }))
    counter = 0
    assert_equal false, V::Still.settle(-> { (counter += 1).to_s })[:stable]
  end

  class Session
    attr_reader :calls

    def initialize(shot) = (@shot = shot) && (@calls = [])
    def evaluate(js, await_promise: false) = (@calls << [js[0, 20], await_promise]) && 2
    def screenshot = @shot
  end

  def test_the_still_shot_freezes_masks_and_settles_fonts_first
    session = Session.new("same")
    result = V::Still.shot(session, mask: [".clock"])

    assert_equal [true, 2], result.values_at(:stable, :masked)
    assert_equal [false, true], session.calls.map(&:last)
  end

  App = Data.define(:name, :port, :dir)

  def surfaces(pages) = V::Surfaces.for_apps([App.new("brgen", 1, "rails/brgen"), App.new("amber", 2, "rails/amber")], paths: (1..pages).map { |p| "/p#{p}" })

  def test_a_capped_pass_takes_mobile_captures_before_any_desktop_one
    picked = V::Surfaces.select(surfaces(20), pass: 1)
    assert_equal 24, picked.size
    assert picked.all?(&:mobile?)
  end

  def test_desktop_only_fills_the_room_left_and_the_phone_width_comes_first
    rows = surfaces(2)
    picked = V::Surfaces.select(rows, pass: 1)

    assert_equal [390] * 4 + [360] * 4 + [320] * 4 + [1280] * 4, picked.map(&:width)
  end

  def test_consecutive_passes_reach_every_mobile_surface
    rows = surfaces(20)
    seen = (1..5).flat_map { |pass| V::Surfaces.select(rows, pass:).map(&:id) }.uniq

    assert_equal rows.select(&:mobile?).map(&:id).sort, seen.sort
    assert_equal rows.size, V::Surfaces.select(rows, pass: 1, cap: 0).size
  end

  def test_the_state_matrix_plans_mobile_first_and_cuts_at_its_cap
    cells = V::StateMatrix.plan
    assert_equal 12, cells.size
    assert_equal ["default", 390], [cells.first.state, cells.first.width]
    assert_equal [390] * 9, cells.first(9).map(&:width)
    assert_equal 18, V::StateMatrix.plan(cap: 99).size, "default, 8 states, 6 widths, zoom, en, dark"
  end

  def test_an_unseen_focus_state_and_an_overflow_are_named_with_their_laws
    base = V::StateMatrix.plan.first
    same = png(4, 4) { WHITE }
    rows = [{ cell: base, shot: same, overflow: false }, { cell: base.with(state: "focus-visible"), shot: same, overflow: false },
            { cell: base.with(width: 320), shot: png(4, 4) { BLACK }, overflow: true }]
    found = V::StateMatrix.judge("brgen/core first action", rows)

    assert_equal 2, found.size
    assert_match(/law=FOCUS_VISIBLE/, found[0])
    assert_match(/320px.*law=INTRINSIC_LAYOUT/, found[1])
    assert_equal [12, 4], V::PixelMatch.read(V::StateMatrix.composite(rows)).size
  end

  def test_axe_rules_map_to_their_laws_and_an_unowned_rule_is_kept
    report = { "violations" => [{ "id" => "image-alt", "nodes" => 2, "impact" => "critical", "target" => "img" },
                                { "id" => "new-rule", "nodes" => 1, "impact" => "minor", "target" => "p" }] }
    found = V::Axe.findings("brgen/core/390", report)

    assert_match(/law=IMG_ALT/, found[0])
    assert_match(/law=unmapped/, found[1])
  end
end
