# frozen_string_literal: true

require_relative "fix_helper"
require_relative "../../master/fix/visual/lane"

# Moved from pub4 MASTER/test/test_visual_independent_review.rb,
# test_visual_simplify.rb's reduction tests (d7314bf0ec),
# test_visual_reference.rb (638074a99f), test_token_ratchets.rb
# (c5c44bb599), test_computed_value_audit.rb (5b187ec31e) and
# test_space_checks.rb (fc00c9f788).
class FixVisualReviewTest < Minitest::Test
  include FixHelper
  V = Fix::Visual
  BOX = { x: 0, y: 0, w: 8, h: 8 }.freeze

  def grey(value) = V::Png.encode(16, 16, ([value, value, value, 255] * 256).pack("C*"))

  def group = V::Group.new(key: "g1", law: "EIGHT_PX_RHYTHM", place: "div.card", surfaces: ["brgen/core/390"],
                           evidence: ["geometry spacing: brgen/core/390 div.card padding-top 10px"], before: grey(255), after: grey(0))

  def reviewer(answer, seen = [])
    Object.new.tap do |r|
      r.define_singleton_method(:ask) do |brief, task: nil|
        seen << brief
        Models::Dispatch::Reply.new(text: answer, model: "r", tokens_in: 0, tokens_out: 0, cost_usd: nil, seconds: 0)
      end
    end
  end

  def test_the_brief_names_the_laws_the_principles_and_every_region_and_the_crops_are_4x
    sandbox do |root|
      world = fix_world(root)
      seen = []
      V::Reviewer.judge(world, group, [BOX], reviewer: reviewer("REJECT: no", seen))

      assert_match(%r{Laws: EIGHT_PX_RHYTHM}, seen.first)
      assert_match(/Swiss.*Bringhurst.*Mueller-Brockmann/m, seen.first)
      crop = seen.first[/R1 0,0 8x8 (\S+)/, 1]
      assert_equal [64, 64], V::PixelMatch.read(File.binread(File.join(root, crop))).size
    end
  end

  def test_only_an_approval_that_explains_every_region_approves
    sandbox do |root|
      world = fix_world(root)
      verdicts = ["APPROVE\nR1: EIGHT_PX_RHYTHM, 10px became 8px\nR2: same rule", "APPROVE\nR1: fine", "REJECT: R2 moved"]
                 .map { |answer| V::Reviewer.judge(world, group, [BOX, BOX], reviewer: reviewer(answer)) }

      assert_equal [:approved, "rejected: R2 left unexplained", "rejected: R2 moved"], verdicts
      assert_equal "no independent reviewer configured", V::Reviewer.judge(world, group, [BOX], reviewer: nil)
    end
  end

  def test_a_guarded_finding_reports_hard_and_a_guard_is_kept_once
    sandbox do |root|
      world = fix_world(root)
      2.times { V::Guards.record(world, kind: "geometry spacing", place: "div.card", surfaces: ["brgen/core/390"]) }
      rows = V::Guards.rows(world)
      marked = V::Guards.mark(["geometry spacing: brgen/core/390 div.card 10px", "geometry spacing: amber/home/390 div.card 10px"], rows)

      assert_equal 1, rows.size
      assert marked[0].end_with?("[guarded]")
      refute marked[1].end_with?("[guarded]")
    end
  end

  def test_the_reviewer_may_not_be_the_author
    router = Object.new.tap { |r| r.define_singleton_method(:chain) { |_| ["claude-cli:opus"] } }
    model = Object.new.tap { |m| m.define_singleton_method(:router) { router } }
    lane = V::Lane.new(world: nil, reviewer: model, author: "claude-cli:opus", chrome: nil, camera: Object.new)

    assert_match(/refused: claude-cli:opus is also the author/, lane.reviewer_note)
  end

  CSS = ".a { color: #111; padding: 8px; }\n.b { padding: 8px; color: #111; }\n:root { --ink: #222; }\n.c { color: #222; }\n"

  def test_simplify_merges_duplicate_rules_tokenises_literals_and_unwraps_divs
    reduced = V::Simplify.reduce(html: "<main><div><p>hi</p></div></main>", css: CSS)

    assert_includes reduced[:css], ".a, .b {"
    assert_includes reduced[:css], "color: var(--ink);"
    assert_equal "<main><p>hi</p></main>", reduced[:html]
    assert_operator V::Simplify.counts(css: reduced[:css])[:total], :<, V::Simplify.counts(css: CSS)[:total]
  end

  def test_simplify_keeps_only_a_falling_count_and_no_visible_change
    counts = ->(n) { { total: n } }
    assert_equal :accepted, V::Simplify.verdict(before: counts[5], after: counts[4], changed_pixels: 0)
    assert_equal :review, V::Simplify.verdict(before: counts[5], after: counts[4], changed_pixels: 3)
    assert_equal :review, V::Simplify.verdict(before: counts[5], after: counts[4], changed_pixels: nil)
    assert_equal :refused, V::Simplify.verdict(before: counts[5], after: counts[5], changed_pixels: 0)
  end

  def test_a_simplified_sheet_with_no_render_and_no_approval_is_put_back
    sandbox do |root|
      put(root, "rails/x/app.scss", CSS)
      world = fix_world(root)
      committed = []
      stage = V::Simplify::Stage.new(world:, shots: ->(_path, &write) { write.call && nil },
                                     review: ->(*) { flunk "nothing to show a reviewer" }, commit: ->(path) { committed << path })

      assert_equal({ "rails/x/app.scss" => :visible_change_not_approved }, stage.run(["rails/x/app.scss"]))
      assert_equal CSS, File.read(File.join(root, "rails/x/app.scss"))
      assert_empty committed
    end
  end

  def test_a_simplified_sheet_that_changes_no_pixel_is_kept
    sandbox do |root|
      put(root, "rails/x/app.scss", CSS)
      world = fix_world(root)
      committed = []
      stage = V::Simplify::Stage.new(world:, shots: ->(_path, &write) { write.call && [[grey(9), grey(9)]] },
                                     review: ->(*) { :approved }, commit: ->(path) { committed << path })

      assert_equal({ "rails/x/app.scss" => :applied }, stage.run(["rails/x/app.scss"]))
      assert_equal ["rails/x/app.scss"], committed
    end
  end

  def test_the_reference_pairs_elements_by_role_and_text_and_reports_deltas
    ours = [{ "tag" => "h1", "text" => "Hei", "frect" => { "x" => 0, "y" => 20, "w" => 100, "h" => 30 }, "font_size" => 36, "color" => "#000" },
            { "role" => "button", "text" => "Go", "frect" => { "x" => 0, "y" => 64, "w" => 80, "h" => 40 }, "font_size" => 16 }]
    theirs = [{ "role" => "button", "text" => "go", "frect" => { "x" => 0, "y" => 60, "w" => 80, "h" => 44 }, "font_size" => 16 },
              { "tag" => "h1", "text" => "Hei", "frect" => { "x" => 0, "y" => 12, "w" => 100, "h" => 30 }, "font_size" => 24, "color" => "#111" }]
    report = V::Reference.report(V::Reference.compare(ours, theirs))

    assert_includes report, "h1 hei: y 8.0, font_size 12.0, color"
    assert_includes report, "button go: y 4.0, h -4.0"
  end

  TOKENS = { space_px: [1, 2], line_height: [1.5], radius_px: [4], palette: ["#123456"], max_font_sizes: 2 }.freeze

  def test_the_computed_audit_names_each_off_token_value_with_its_law
    elements = [{ "key" => "p.a", "visible" => true, "text" => "x", "font_size" => 13.5, "line_height" => 24, "spacing" => [10, 8],
                  "border_radius" => "6px", "bg" => "#abcdef", "frect" => { "w" => 100, "h" => 40 } },
                { "key" => "h1", "visible" => true, "text" => "y", "font_size" => 30, "line_height" => 45 },
                { "key" => "small", "visible" => true, "text" => "z", "font_size" => 12, "line_height" => 18 }]
    found = V::Audit.computed("brgen/core/390", elements, TOKENS).join("\n")

    %w[EIGHT_PX_RHYTHM LINE_HEIGHT_ON_SCALE RENDERED_VALUES MAGIC_COLOR PIXEL_EXACT TYPE_HIERARCHY].each { |law| assert_includes found, "law=#{law}" }
    assert_empty V::Audit.computed("s", [{ "key" => "ok", "visible" => true, "text" => "x", "font_size" => 16, "line_height" => 24, "spacing" => [8, 2] }], TOKENS)
  end

  def test_space_checks_find_a_crowded_edge_a_void_and_an_unbalanced_heading
    elements = [{ "key" => "h1", "tag" => "h1", "visible" => true, "text" => "T", "text_lines" => 2, "frect" => { "x" => 4, "y" => 0, "w" => 300, "h" => 80 } },
                { "key" => "p", "tag" => "p", "visible" => true, "text" => "b", "frect" => { "x" => 16, "y" => 500, "w" => 300, "h" => 20 } }]
    found = V::Audit.space("brgen/core/390", height: 844, width: 390, elements:).join("\n")

    assert_match(/edge_crowding.*h1 4px from the edge/, found)
    assert_match(/void.*empty band/, found)
    assert_match(/heading_wrap.*law=HEADING_WRAP_BALANCE/, found)
    assert_match(/minimalism: .* elements=2/, found)
  end

  def test_the_census_counts_distinct_values_and_off_token_colours
    css = "a{color:#111;padding:8px}b{color:#111;padding:4px}c{color:rgb(1,2,3);margin:0}"

    assert_equal [2, 2], V::Census.counts(css).values_at("padding", "color")
    assert_equal [["padding", 2, 1]], V::Census.over(css, { "padding" => 1, "color" => 5 })
    assert_equal ["rgb(1,2,3)"], V::Census.off_token_colors(css, ["#111"])
  end
end
