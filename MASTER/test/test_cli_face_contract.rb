# frozen_string_literal: true

require "minitest/autorun"
require "yaml"

class CliFaceContractTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  # The terminal face is retired: the face is the web particle face only
  # (Johann 2026-11-07). The tokens it shared with the web renderer stay
  # governed by the contract.
  def test_terminal_depth_tones_are_neutral_and_motion_is_bounded
    tokens = YAML.safe_load_file(File.join(ROOT, "data", "tokens.yml"), aliases: true).fetch("tokens")
    ascii = tokens.fetch("face_interface").fetch("ascii")
    %w[tone_far tone_mid tone_near].each do |key|
      rgb = ascii.fetch(key).delete("#").scan(/../).map { |channel| channel.to_i(16) }
      assert_equal 3, rgb.size
      assert_equal rgb.first, rgb[1], "#{key} must be grayscale"
      assert_equal rgb.first, rgb[2], "#{key} must be grayscale"
    end
    motion = ascii.fetch("motion")
    assert_equal [0.28, 1.85], motion.fetch("glance_interval")
    assert_operator motion.fetch("glance_horizontal"), :<, 0.08
    assert_operator motion.fetch("glance_vertical"), :<, 0.04
  end
end
