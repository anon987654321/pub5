# frozen_string_literal: true

begin
  require "vips"
rescue LoadError
  # fall through: the bind check below is the real verdict
end
# The gem can load without binding the system library until Vips::Image is
# touched, so the verdict is the constant, not the require's success.
POSTPRO_VIPS_OK = defined?(Vips::Image) ? true : false
require_relative "minitest_helper"
require_relative "../postpro/legacy_effects"

class PostproLegacyEffectHarness
  include Postpro::LegacyEffects

  def safe_cast(image)
    float = image.cast("float")
    float = (float > 0).ifthenelse(float, 0)
    float = (float < 255).ifthenelse(float, 255)
    float.cast("uchar")
  end
end

class TestPostproSuper8Flicker < Minitest::Test

  def setup
    skip "system libvips absent - ruby-vips cannot bind; install libvips to run postpro" unless POSTPRO_VIPS_OK
    @effects = PostproLegacyEffectHarness.new
  end

  def test_still_image_does_not_fabricate_temporal_flicker
    image = image_from_pixels([128, 128, 128, 64, 64, 64])

    assert_same image, @effects.super8_flicker(image, 0.78)
  end

  def test_video_flicker_changes_the_whole_frame_by_one_linear_exposure_factor
    source = [128, 128, 128, 64, 64, 64]
    image = image_from_pixels(source)
    output = @effects.super8_flicker(image, 1.0, exposure_ev: 0.125)
    pixels = output.write_to_memory.unpack("C*")
    multiplier = 2.0**0.125

    source.each_slice(3).with_index do |pixel, index|
      before = srgb_to_linear(pixel.first / 255.0)
      after = srgb_to_linear(pixels.drop(index * 3).first / 255.0)

      assert_in_delta multiplier, after / before, 0.012
    end
  end

  def test_non_finite_or_unbounded_exposure_is_rejected
    image = image_from_pixels([128, 128, 128])

    assert_raises(ArgumentError) do
      @effects.super8_flicker(image, 1.0, exposure_ev: Float::INFINITY)
    end
    assert_raises(ArgumentError) do
      @effects.super8_flicker(image, 1.0, exposure_ev: 0.251)
    end
  end

  private

  def image_from_pixels(pixels)
    width = pixels.length / 3
    raise ArgumentError, "RGB test pixels must contain complete triples" unless width.positive? && (pixels.length % 3).zero?

    Vips::Image.new_from_memory(pixels.pack("C*"), width, 1, 3, :uchar)
                .copy(interpretation: :srgb)
  end

  def srgb_to_linear(value)
    value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055)**2.4
  end
end
