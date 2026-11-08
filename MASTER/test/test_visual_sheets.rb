# frozen_string_literal: true

require_relative "test_helper"
require_relative "../tools/visual/sheets"

# The pure half of the screenshot-review sheet tool: crop parsing, row
# partitioning and scaling. The libvips call sequence is not exercised here;
# a rendered sheet is rendered evidence and stays with the screenshot
# workflow that consumes it.
class TestVisualSheets < Minitest::Test
  Sheets = Master::Visual::Sheets

  def test_crop_parses_four_positive_integers
    assert_equal [0, 18, 900, 64], Sheets.parse_crop("0,18,900,64")
    assert_equal [380, 30, 720, 180], Sheets.parse_crop("380,30,720,180")
  end

  def test_crop_refuses_the_wrong_shape_and_nonpositive_sizes
    assert_raises(ArgumentError) { Sheets.parse_crop("0,18,900") }
    assert_raises(ArgumentError) { Sheets.parse_crop("0,18,900,64,2") }
    assert_raises(ArgumentError) { Sheets.parse_crop("0,18,0,64") }
    assert_raises(ArgumentError) { Sheets.parse_crop("0,18,900,-5") }
    assert_raises(ArgumentError) { Sheets.parse_crop("-1,18,900,64") }
    assert_raises(ArgumentError) { Sheets.parse_crop("left,top,900,64") }
  end

  def test_rows_partition_tiles_column_major
    tiles = (1..7).to_a

    assert_equal [[1, 2, 3], [4, 5, 6], [7]], Sheets.rows(tiles, columns: 3)
    assert_equal [[1, 2], [3, 4], [5, 6], [7]], Sheets.rows(tiles, columns: 2)
    assert_equal [tiles], Sheets.rows(tiles, columns: 8)
  end

  def test_rows_refuses_a_nonpositive_column_count
    assert_raises(ArgumentError) { Sheets.rows([1], columns: 0) }
  end

  def test_scale_is_the_ratio_of_target_to_source_width
    assert_in_delta 730.0 / 1460, Sheets.scale_for(730, 1460)
    assert_in_delta 1.0, Sheets.scale_for(390, 390)
  end

  def test_scale_refuses_degenerate_widths
    assert_raises(ArgumentError) { Sheets.scale_for(0, 100) }
    assert_raises(ArgumentError) { Sheets.scale_for(100, 0) }
  end

  def test_labels_derive_from_the_file_name_without_its_extension
    assert_equal "brgen-desktop", Sheets.label_for("RAILS/docs/screenshots/brgen-desktop.png")
    assert_equal "01-menu", Sheets.label_for("01-menu.PNG")
  end
end
