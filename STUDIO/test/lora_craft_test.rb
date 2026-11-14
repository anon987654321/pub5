# frozen_string_literal: true

require_relative "minitest_helper"
require_relative "../lora/lora"

class TestStudioLoraCraft < Minitest::Test
  def test_shared_photographic_craft_does_not_force_one_film_stock
    refute_includes Studio::Lora::Craft::PHOTOGRAPHIC_CRAFT, "Portra"
    refute Studio::Lora::Craft.const_defined?(:HOUSE_STOCK, false)
  end

  def test_every_default_sitting_has_a_distinct_stock_instruction
    prompts = Studio::Lora::Selfie::SCENES.each_index.map do |index|
      Studio::Lora::Selfie.scene(index + 1)
    end
    assert_equal 10, prompts.length
    Studio::Lora::Selfie::SCENE_STOCKS.each do |stock|
      description = Studio::Lora::Craft::STOCK.fetch(stock)
      assert prompts.any? { |prompt| prompt.include?(description) }
    end
    assert_equal 10, Studio::Lora::Selfie::SCENE_STOCKS.uniq.length
  end
end
