# frozen_string_literal: true

require_relative "test_helper"

class DesignDirectionTest < Minitest::Test
  Surface = Struct.new(:id, :app, :label, :host, :path)

  def test_vertical_direction_uses_product_before_shared_host
    language = Master::Design::VisualLanguage
    {
      ["brgen", "marketplace.brgen.no", "/takeaway/restaurants"] => :transactional_food,
      ["brgen", "marketplace.brgen.no", "/food"] => :transactional_food,
      ["brgen", "dating.brgen.no", "/"] => :intimate_social,
      ["brgen", "radio.brgen.no", "/sets"] => :media_station,
      ["brgen", "tv.brgen.no", "/"] => :media_station,
      ["brgen", "maps.brgen.no", "/"] => :cartographic,
      ["amber", "amberapp.art", "/messages"] => :editorial_wardrobe,
      ["master", "ai.brgen.no", "/"] => :conversational,
      ["mrdamascy", "mrd.brgen.no", "/orders"] => :transactional_food,
      ["bsdports", "bsdports.org", "/ports"] => :utilitarian_terminal,
    }.each do |(app, host, path), direction|
      surface = Surface.new("#{app}#{path}", app, path, host, path)
      assert_equal direction, language.direction_for(surface), surface.id
      assert_includes language.surface_anatomy(surface), "interaction_patterns="
    end
  end

  def test_authority_is_first
    contract = Master::Design::Authority.contract
    assert_equal 1, contract.fetch("priority")
    assert_equal %w[purpose agency clarity hierarchy trust consistency craft delight],
                 Master::Design::Authority::ORDER
  end

  def test_all_schools_inherit_authority
    Master::Design::Authority.schools.each do |name, spec|
      assert_equal true, spec.fetch("inherits_authoritative_design"), "#{name} bypasses authority"
    end
  end

  def test_marketplace_pairing_is_shipped_and_single_family
    key, spec = Master::Design::Pairing.for(school: :commerce_editorial, purpose: "marketplace sale")
    assert_equal "marketplace_sale", key
    assert_equal "house_sans", spec.fetch("display")
    assert Master::Design::Pairing.deployable?(spec)
  end

  def test_marketplace_composition_preserves_transaction_priority
    _, spec = Master::Design::Composition.for(school: :commerce_editorial, purpose: "marketplace sale")
    assert_equal %w[product price headline proof action], spec.fetch("focal_order")
  end

  def test_measure_accessor_delegates_to_thresholds
    assert_equal Master::Design::Thresholds.measure_ideal_ch,
                 Master::Design.measure_ideal_ch
  end

  def test_every_declared_editorial_profile_is_selectable_by_description
    profiles = Master::Design::PlatformProfiles

    assert_equal :medium, profiles.choose("Medium long-form reading")
    assert_equal :new_yorker, profiles.choose("New Yorker editorial magazine")
    assert_equal :x, profiles.choose("X real-time timeline")
  end
end
