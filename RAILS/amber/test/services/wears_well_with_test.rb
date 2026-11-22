# frozen_string_literal: true

require "test_helper"

# Wears-well-with from typed attributes: explainable, brute-force, wardrobe
# scale. The matches must name what they share, an item with no typed
# attributes must match nothing rather than guess, and a retired garment must
# not come back as a suggestion.
class WearsWellWithTest < ActiveSupport::TestCase
  def owner(email)
    User.strict_loading(false).create!(email_address: email, password: "password")
  end

  def garment(owner, title, **attributes)
    Item.create!(user: owner, title: title, **attributes)
  end

  test "neighbors name the shared typed attributes that produced the match" do
    owner = owner("www-summer@example.com")
    summer_dress = garment(owner, "Linen dress", category: "Dresses", material: "linen",
                                       season: "summer", occasion_tags: "work travel")
    summer_shoes = garment(owner, "Linen sandals", category: "Shoes", material: "linen",
                                        season: "summer", occasion_tags: "travel")
    winter_coat = garment(owner, "Wool coat", category: "Outerwear", material: "wool",
                                    season: "winter")

    matches = WearsWellWith.new(summer_dress).neighbors

    best = matches.first
    assert_equal summer_shoes.id, best[:item].id
    assert_includes best[:shared], "material:linen"
    assert_includes best[:shared], "season:summer"
    assert_includes best[:shared], "occasion_tags:travel"
    assert_predicate best[:similarity], :positive?
    assert_empty(matches.filter_map { |m| m[:item].id if m[:item].id == winter_coat.id },
                 "a winter wool coat shares nothing with a summer linen dress")
  end

  test "an item with only its required category matches nothing instead of guessing" do
    owner = owner("www-blank@example.com")
    # category is mandatory on Item, so "no typed attributes" means: the
    # required category and nothing else. Paired with an item sharing no
    # typed token, the honest answer is an empty list, not a guess.
    blank = garment(owner, "Plain dress", category: "Dresses")
    garment(owner, "Wool coat", category: "Outerwear", material: "wool")

    assert_empty WearsWellWith.new(blank).neighbors
    assert_equal [ "category:dresses" ], WearsWellWith.new(blank).tokens
  end

  test "retired and inactive garments are not suggested" do
    owner = owner("www-retired@example.com")
    dress = garment(owner, "Linen dress", category: "Dresses", material: "linen", season: "summer")
    retired = garment(owner, "Retired linen dress", category: "Dresses", material: "linen",
                                season: "summer", lifecycle_state: "retired")

    refute_includes WearsWellWith.new(dress).neighbors.filter_map { |m| m[:item].id },
                    retired.id
  end

  test "the match stays inside one owner's wardrobe" do
    mine = owner("www-mine@example.com")
    theirs = owner("www-theirs@example.com")
    dress = garment(mine, "Linen dress", category: "Dresses", material: "linen")
    foreign = garment(theirs, "Their linen dress", category: "Dresses", material: "linen")

    refute_includes WearsWellWith.new(dress).neighbors.filter_map { |m| m[:item].id }, foreign.id
  end

  test "cosine answers the arithmetic it claims, on the item itself" do
    owner = owner("www-cosine@example.com")
    dress = garment(owner, "Dress", category: "Dresses", season: "summer")
    twin = garment(owner, "Twin dress", category: "Dresses", season: "summer")
    half = garment(owner, "Half share", category: "Dresses")

    service = WearsWellWith.new(dress)
    score_twin, shared_twin = service.compare(twin)
    score_half, = service.compare(half)

    # Two tokens out of two: identical typed vectors score 1.
    assert_in_delta 1.0, score_twin, 1e-9
    assert_equal %w[category:dresses season:summer], shared_twin.sort
    # One shared token of two and one: 1 / sqrt(2 * 1) = 0.707.
    assert_in_delta 0.7071, score_half, 1e-3
  end

  test "items#wears_well_with is the one entry the surfaces call" do
    owner = owner("www-entry@example.com")
    dress = garment(owner, "Linen dress", category: "Dresses", material: "linen")
    garment(owner, "Linen shirt", category: "Shirts", material: "linen")

    matches = dress.wears_well_with
    assert_equal 1, matches.size
    assert_includes matches.first[:shared], "material:linen"
  end
end
