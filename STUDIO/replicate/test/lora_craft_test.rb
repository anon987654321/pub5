# frozen_string_literal: true

require_relative "minitest_helper"
require_relative "../../lora/lora"

class TestStudioLoraCraft < Minitest::Test
  # Black Forest Labs asks for the medium and style first, so the stock opens
  # the caption instead of trailing it as a tag.
  # Her renders first settled too old, then too young. The descriptor keeps the
  # age it now states, and the scenes keep a shadow side without a hard edge or
  # a claim of flawless skin.
  def test_ragnhild_keeps_her_age_and_a_modelled_face
    descriptor = File.read(File.expand_path("../../lora/ragnhild/subject.env", __dir__))
    assert_includes descriptor, "in her forties"
    refute_includes descriptor, "smooth fair skin"

    scenes = Studio::Lora::Selfie::SUBJECT_SCENES.fetch("ragnhild")
    refute(scenes.any? { |scene| scene.include?("no hard shadow edge") }, "shadowless light reads young")
    refute(scenes.any? { |scene| scene.include?("soft even skin") }, "flawless skin reads young")
    assert(scenes.any? { |scene| scene.include?("shadow side") }, "the studio sitting keeps a modelled face")
  end

  # A chain that develops nothing hands back the frame as the model left it, so
  # the house look would be a second grade over a film character already in the
  # pixels. The stack crushed the midtones; one portrait grade carries the frame.
  def test_an_untouched_frame_takes_one_portrait_grade
    craft = Studio::Lora::Craft
    assert_equal ["portrait", []],
                 craft.development(chain: "native", preset: "house", chain_presets: %w[aged_kodachrome])
    assert_equal ["house", %w[aged_kodachrome]],
                 craft.development(chain: "stills", preset: "house", chain_presets: %w[aged_kodachrome])
    assert_equal ["house", %w[aged_kodachrome]],
                 craft.development(chain: "vintage", preset: "house", chain_presets: %w[aged_kodachrome])
    assert_equal [nil, %w[aged_kodachrome]],
                 craft.development(chain: "native", preset: nil, chain_presets: %w[aged_kodachrome])
  end

  def test_the_scene_opens_with_the_film_stock
    scene = Studio::Lora::Selfie.scene(1, subject: "johann")

    assert Studio::Lora::Craft::STOCK.values.any? { |stock| scene.start_with?(stock) },
           "expected a stock clause at the start of: #{scene[0, 80]}"
  end

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

  def test_phone_selfie_is_an_explicit_arm_length_study
    default = Studio::Lora::Selfie.scene(1)
    phone = Studio::Lora::Selfie.scene(1, phone: true)

    refute_match(/24mm-equivalent/, default)
    assert_match(/24mm-equivalent phone lens/, phone)
    assert_match(/arm's length/, phone)
    refute_match(/\b(?:35|50|85)mm\b/, phone)
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
  def test_recovered_catalogue_and_default_series
    selfie = Studio::Lora::Selfie
    archive = Studio::Lora::Guides.load.fetch("historical_sittings")
    assert_equal 74, archive.fetch("ideas").size
    assert_equal 24, archive.fetch("best").size
    assert_equal 200, (1..200).map { |n| selfie.scenario_recipe(n).fetch("scene") }.uniq.size
    %w[johann ragnhild merethe].each do |subject|
      recipes = (1..4).map { |n| selfie.recipe(n, subject:) }
      assert recipes[1].key?("historical_source")
      assert_match(/camera distance:/, recipes[3].fetch("scene"))
      refute_includes recipes[1].fetch("scene"), '#{'
    end
    %w[shoots warp best].each do |direction|
      assert selfie.historical_recipe(1, direction:).fetch("historical_title")
    end
  end
end
