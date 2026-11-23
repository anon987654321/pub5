# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "fileutils"
require_relative "../checks/support/visual_register"

class TestVisualRegister < Minitest::Test
  # Tiny in-memory PNGs through PngDiff's own codec: the composite modes are
  # pure pixel functions, so exact byte-level assertions pin them without a
  # browser ever opening.
  def write_png(dir, name, width, height, pixels)
    path = File.join(dir, name)
    File.binwrite(path, Deploy::PngDiff.encode_rgba(width, height, pixels.flatten.pack("C*")))
    path
  end

  def pixel(path, x, y)
    img = Deploy::PngDiff.decode(File.binread(path))
    row_bytes = img[:width] * img[:channels]
    row = previous = Array.new(row_bytes, 0)
    (y + 1).times do |yy|
      line = img[:raw].byteslice(yy * (row_bytes + 1), row_bytes + 1)
      row = Deploy::PngDiff.unfilter_row(line, previous:, channels: img[:channels])
      previous = row
    end
    i = x * img[:channels]
    [row[i], row[i + 1], row[i + 2]]
  end

  def solid(dir, name, rgb, width: 2, height: 2)
    write_png(dir, name, width, height, Array.new(width * height) { rgb + [255] })
  end

  def test_anaglyph_of_identical_captures_reads_gray
    Dir.mktmpdir do |dir|
      a = solid(dir, "a.png", [10, 200, 90])
      out = File.join(dir, "out.png")
      result = Deploy::VisualRegister.composite(a_path: a, b_path: a, mode: "anaglyph", out_path: out)
      assert_equal :composited, result[:status]
      assert_equal [10, 200, 90], pixel(out, 0, 0)
      assert_equal [10, 200, 90], pixel(out, 1, 1)
    end
  end

  def test_anaglyph_keeps_a_in_red_and_b_in_cyan
    Dir.mktmpdir do |dir|
      a = solid(dir, "a.png", [255, 0, 0])
      b = solid(dir, "b.png", [0, 0, 255])
      out = File.join(dir, "out.png")
      Deploy::VisualRegister.composite(a_path: a, b_path: b, mode: "anaglyph", out_path: out)
      assert_equal [255, 0, 255], pixel(out, 0, 0) # red from A, green+blue from B
    end
  end

  def test_difference_is_black_where_identical_and_amplified_where_not
    Dir.mktmpdir do |dir|
      a = solid(dir, "a.png", [100, 100, 100])
      b = solid(dir, "b.png", [110, 90, 100])
      same = File.join(dir, "same.png")
      drift = File.join(dir, "drift.png")
      Deploy::VisualRegister.composite(a_path: a, b_path: a, mode: "difference", out_path: same)
      Deploy::VisualRegister.composite(a_path: a, b_path: b, mode: "difference", out_path: drift, amplify: 4)
      assert_equal [0, 0, 0], pixel(same, 1, 1)
      assert_equal [40, 40, 0], pixel(drift, 1, 1)
    end
  end

  def test_difference_clamps_instead_of_wrapping
    Dir.mktmpdir do |dir|
      a = solid(dir, "a.png", [255, 0, 0])
      b = solid(dir, "b.png", [0, 0, 0])
      out = File.join(dir, "out.png")
      Deploy::VisualRegister.composite(a_path: a, b_path: b, mode: "difference", out_path: out, amplify: 4)
      assert_equal [255, 0, 0], pixel(out, 0, 0) # 255 * 4 would wrap without the clamp
    end
  end

  def test_overlay_blends_half_and_half
    Dir.mktmpdir do |dir|
      a = solid(dir, "a.png", [0, 100, 200])
      b = solid(dir, "b.png", [100, 100, 100])
      out = File.join(dir, "out.png")
      Deploy::VisualRegister.composite(a_path: a, b_path: b, mode: "overlay", out_path: out)
      assert_equal [50, 100, 150], pixel(out, 1, 0)
    end
  end

  def test_checkerboard_alternates_per_tile
    Dir.mktmpdir do |dir|
      a = solid(dir, "a.png", [255, 0, 0], width: 2, height: 2)
      b = solid(dir, "b.png", [0, 0, 255], width: 2, height: 2)
      out = File.join(dir, "out.png")
      Deploy::VisualRegister.composite(a_path: a, b_path: b, mode: "checkerboard", out_path: out, tile: 1)
      assert_equal [255, 0, 0], pixel(out, 0, 0)
      assert_equal [0, 0, 255], pixel(out, 1, 0)
      assert_equal [0, 0, 255], pixel(out, 0, 1)
      assert_equal [255, 0, 0], pixel(out, 1, 1)
    end
  end

  def test_dimension_mismatch_refuses_to_guess
    Dir.mktmpdir do |dir|
      a = solid(dir, "a.png", [0, 0, 0], width: 2, height: 2)
      b = solid(dir, "b.png", [0, 0, 0], width: 4, height: 2)
      result = Deploy::VisualRegister.composite(a_path: a, b_path: b, mode: "anaglyph",
                                                out_path: File.join(dir, "out.png"))
      assert_equal :dimension_mismatch, result[:status]
      assert_nil result[:composite_image]
    end
  end

  def test_unknown_mode_is_refused
    Dir.mktmpdir do |dir|
      a = solid(dir, "a.png", [0, 0, 0])
      assert_raises(ArgumentError) do
        Deploy::VisualRegister.composite(a_path: a, b_path: a, mode: "sepia", out_path: File.join(dir, "o.png"))
      end
    end
  end

  def test_grid_overlay_tints_lines_and_leaves_interiors
    Dir.mktmpdir do |dir|
      a = solid(dir, "a.png", [0, 0, 0], width: 4, height: 4)
      out = File.join(dir, "out.png")
      Deploy::VisualRegister.grid_overlay(capture_path: a, out_path: out, spacing: 2)
      on_line = pixel(out, 1, 0) # y == 0 is a (major) grid line over black
      off_line = pixel(out, 1, 1)
      assert_equal [0, 0, 0], off_line
      assert_equal 0, on_line[0]
      assert_operator on_line[1], :>, 0 # cyan ink, green/blue channels only
      assert_equal on_line[1], on_line[2]
    end
  end
end
