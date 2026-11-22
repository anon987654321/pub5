# frozen_string_literal: true

require "minitest/autorun"

# amber_similarity_right_sized (MASTER/data/gaps.yml, convergence workstream):
# wears-well-with from typed attribute vectors, brute-force cosine, wardrobe
# scale. The service class is pure Ruby over the item's typed fields, so this
# contract loads it on a bare Ruby and proves the arithmetic, the token
# namespacing and the honesty rules: a blank garment matches nothing, tokens
# are namespaced per field so "blue" a colour and "blue" a mood never meet,
# and every match carries the reason it matched.
class WearsWellWithContractTest < Minitest::Test
  SERVICE = File.expand_path("../amber/app/services/wears_well_with.rb", __dir__)

  ItemStub = Struct.new(:category, :color, :material, :season, :mood_effect, :life_phase, :occasion_tags,
                        keyword_init: true)

  def load_service
    Object.send(:remove_const, :WearsWellWith) if defined?(WearsWellWith)
    load SERVICE
  end

  def test_cosine_is_the_intersection_over_the_geometric_mean
    load_service
    dress = ItemStub.new(category: "Dresses", season: "Summer", material: "Linen",
                         occasion_tags: "work travel")
    twin = ItemStub.new(category: "Dresses", season: "Summer", material: "Linen")

    score, shared = WearsWellWith.new(dress).compare(twin)

    # Three shared tokens over sqrt(5 * 3).
    assert_in_delta(3.0 / Math.sqrt(15.0), score, 1e-9)
    assert_equal %w[category:dresses material:linen season:summer], shared
  end

  def test_tokens_are_namespaced_per_field_and_case_folded
    load_service
    garment = ItemStub.new(category: "Dresses", color: "Blue", mood_effect: "Calm",
                           occasion_tags: "Work  travel")

    assert_equal ["category:dresses", "color:blue", "mood_effect:calm",
                  "occasion_tags:travel", "occasion_tags:work"],
                 WearsWellWith.tokens_for(garment).sort
  end

  def test_a_blank_garment_contributes_no_tokens_and_matches_nothing
    load_service
    blank = ItemStub.new
    dress = ItemStub.new(category: "Dresses", season: "Summer")

    assert_empty WearsWellWith.tokens_for(blank)
    assert_equal [0.0, []], WearsWellWith.new(blank).compare(dress)
  end

  def test_no_dimension_is_an_embedding_index_or_a_hidden_model
    source = File.read(SERVICE).lines.reject { |line| line.lstrip.start_with?("#") }.join

    refute_match(/Embedding|pgvector|OpenAI|model/i, source,
                 "the right-sized answer reads typed attributes, nothing learned")
    assert_includes source, "where.not(id: item.id)", "the brute force scans the owner's real wardrobe"
    assert_includes source, "lifecycle_state: \"active\"", "retired garments are not suggestions"
    assert_includes source, "user_id: item.user_id", "a wardrobe is one owner's"
    assert_match(/def neighbors\(limit: 4, minimum: 0\.2\)/, source,
                 "the surface takes its bounds as named arguments")
  end

  def test_the_item_model_exposes_one_entry_point
    source = File.read(File.expand_path("../amber/app/models/item.rb", __dir__))

    assert_includes source, "def wears_well_with(limit: 4, minimum: 0.2)",
                    "items#show and the outfit builders call one method, not the service's internals"
    assert_includes source, "WearsWellWith.new(self).neighbors"
  end

  def test_the_rails_bundle_test_covers_the_wardrobe_rules
    test_path = File.expand_path("../amber/test/services/wears_well_with_test.rb", __dir__)
    source = File.read(test_path)

    assert_includes source, "retired and inactive garments are not suggested"
    assert_includes source, "stays inside one owner's wardrobe"
    assert_includes source, "matches nothing instead of guessing"
  end
end
