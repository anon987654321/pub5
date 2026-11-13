# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../lib/fix/screenshot_sweep"

# The review set at RAILS/screenshot_*.png is replaced whole by each sweep, and
# old sweep folders are pruned, so neither keeps growing. A published shot is
# numbered by its capture position, so the set reads in sweep order.
class TestScreenshotReviewSet < Minitest::Test
  Row = Data.define(:app, :shots)
  ReviewSet = Master::Fix::ScreenshotSweep::ReviewSet
  SWEEPS = %w[sweep-20261101T000000Z sweep-20261102T000000Z sweep-20261103T000000Z sweep-20261104T000000Z].freeze

  def png(path)
    FileUtils.mkdir_p(File.dirname(path))
    File.binwrite(path, "PNG")
  end

  def test_a_sweep_replaces_the_whole_review_set_with_its_phone_width_shots
    Dir.mktmpdir do |root|
      rails = File.join(root, "RAILS")
      sweep = File.join(root, "MASTER", ".master", "visual_artifacts", SWEEPS.last)
      png(File.join(rails, "screenshot_amber_gone.png"))
      png(File.join(rails, "screenshot_99_amber_old.png"))
      png(File.join(rails, "keep_me.png"))
      %w[w390 w1280].each { |width| png(File.join(sweep, "brgen", "brgen_no", "#{width}.png")) }
      shots = { "390" => "brgen/brgen_no/w390.png", "1280" => "brgen/brgen_no/w1280.png" }

      assert_equal 1, ReviewSet.new(root:, sweep_dir: sweep).publish!([Row.new(app: "brgen", shots:)])
      assert_equal %w[keep_me.png screenshot_1_brgen_frontpage.png], Dir.children(rails).sort
    end
  end

  def test_the_published_number_follows_capture_order_across_pages
    Dir.mktmpdir do |root|
      sweep = File.join(root, "sweep-20261104T000000Z")
      # amber answers on loopback (slug "root"); brgen's apex slugs as "brgen_no".
      %w[amber/root brgen/brgen_no].each { |dir| png(File.join(sweep, dir, "w390.png")) }
      rows = %w[amber/root brgen/brgen_no].map { |dir| Row.new(app: dir.split("/").first, shots: { "390" => "#{dir}/w390.png" }) }

      assert_equal 2, ReviewSet.new(root:, sweep_dir: sweep).publish!(rows)
      assert_equal %w[screenshot_1_amber_frontpage.png screenshot_2_brgen_frontpage.png],
                   Dir.children(File.join(root, "RAILS")).sort
    end
  end

  # The brgen apex is a host slug, not "root"; it is still that app's front page.
  # A vertical's root keeps its host, so dating.brgen.no stays distinct.
  def test_only_the_apps_own_front_page_is_named_frontpage
    Dir.mktmpdir do |root|
      sweep = File.join(root, "sweep-20261104T000000Z")
      %w[brgen/brgen_no brgen/dating_brgen_no].each { |dir| png(File.join(sweep, dir, "w390.png")) }
      rows = [{ "390" => "brgen/brgen_no/w390.png" }, { "390" => "brgen/dating_brgen_no/w390.png" }]
                    .map { |shots| Row.new(app: "brgen", shots:) }

      assert_equal 2, ReviewSet.new(root:, sweep_dir: sweep).publish!(rows)
      assert_equal %w[screenshot_1_brgen_frontpage.png screenshot_2_brgen_dating_brgen_no.png],
                   Dir.children(File.join(root, "RAILS")).sort
    end
  end

  def test_a_sweep_that_captured_nothing_leaves_no_review_set
    Dir.mktmpdir do |root|
      png(File.join(root, "RAILS", "screenshot_1_brgen_frontpage.png"))

      assert_equal 0, ReviewSet.new(root:, sweep_dir: File.join(root, "sweep-x")).publish!([])
      refute File.exist?(File.join(root, "RAILS", "screenshot_1_brgen_frontpage.png")),
             "a stale shot must never survive a sweep that rendered nothing"
    end
  end

  def test_only_the_newest_sweeps_are_kept_and_nothing_else_is_touched
    Dir.mktmpdir do |root|
      base = File.join(root, "visual_artifacts")
      (SWEEPS + %w[notes]).each { |name| FileUtils.mkdir_p(File.join(base, name)) }

      pruned = ReviewSet.new(root:, sweep_dir: File.join(base, SWEEPS.last)).prune!

      assert_equal 2, pruned
      assert_equal %w[notes] + SWEEPS.last(2), Dir.children(base).sort
    end
  end
end
