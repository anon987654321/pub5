# frozen_string_literal: true

require_relative "minitest_helper"

begin
  require_relative "../../lora/quality"
rescue LoadError => error
  # quality.rb pulls in vips for the perceptual hashing; a machine without
  # the gem still runs the rest of the suite.
  warn "skipping dataset diversity tests: #{error.message}"
  return
end

# A training set of twelve photographs that are really four frames in
# disguise trains a smaller model than the count promises. The diversity
# audit's pure logic - Hamming distance and near-duplicate pairing - is
# pinned here without images.
class TestStudioLoraDatasetDiversity < Minitest::Test
  Quality = Studio::Lora::Quality

  def test_hamming_counts_differing_bits
    assert_equal 0, Quality.hamming(0b1010, 0b1010)
    assert_equal 1, Quality.hamming(0b1010, 0b1011)
    assert_equal 4, Quality.hamming(0b0000, 0b1111)
  end

  def test_distinct_hashes_produce_no_pairs
    hashes = [["a.jpg", 0x0000], ["b.jpg", 0xFFFF], ["c.jpg", 0x5A5A]]
    assert_empty Quality.near_duplicate_pairs(hashes)
  end

  def test_close_hashes_are_flagged_with_their_distance
    hashes = [["a.jpg", 0b11110000], ["b.jpg", 0b11110001], ["c.jpg", 0xABCDEF]]
    pairs = Quality.near_duplicate_pairs(hashes, threshold: 5)
    assert_equal 1, pairs.length
    assert_equal %w[a.jpg b.jpg], pairs.first.fetch("pair")
    assert_equal 1, pairs.first.fetch("distance")
  end

  def test_threshold_boundary_is_inclusive
    hashes = [["a.jpg", 0b100000], ["b.jpg", 0b000000]]
    assert_empty Quality.near_duplicate_pairs(hashes, threshold: 0)
    assert_equal 1, Quality.near_duplicate_pairs(hashes, threshold: 1).length
  end
end
