# frozen_string_literal: true

require_relative "minitest_helper"
require_relative "../../lora/lora"

class TestStudioLoraCraft < Minitest::Test
  def test_shared_photographic_craft_carries_composition_without_forcing_one_stock
    assert_includes Studio::Lora::Craft::PHOTOGRAPHIC_CRAFT, Studio::Lora::Craft::COMPOSITION
    assert_match(/visual centre/, Studio::Lora::Craft::COMPOSITION)
    assert_match(/negative space/, Studio::Lora::Craft::COMPOSITION)
    refute_includes Studio::Lora::Craft::PHOTOGRAPHIC_CRAFT, "Portra"
    refute Studio::Lora::Craft.const_defined?(:HOUSE_STOCK, false)
  end

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

  def test_first_four_subject_sittings_use_fw26_wardrobe_directions
    scenes = Studio::Lora::Selfie::SUBJECT_SCENES

    assert_match(/herringbone|Fair Isle/i, scenes.fetch("johann").first)
    assert_match(/suede|leather/i, scenes.fetch("johann")[2])
    assert_match(/oxblood|silk-charmeuse/i, scenes.fetch("ragnhild").first)
    assert_match(/velvet/i, scenes.fetch("ragnhild")[1])
    assert_match(/shearling|cashmere/i, scenes.fetch("merethe").first)
    assert_match(/velvet/i, scenes.fetch("merethe")[1])
    refute scenes.values.flatten.first(4).any? { |scene| scene.match?(/Net-a-Porter|MR Porter/i) }
  end
end
