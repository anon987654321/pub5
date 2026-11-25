# frozen_string_literal: true

require_relative "minitest_helper"
require_relative "../../postpro/lib/recipe"

class TestPostproRecipeCompat < Minitest::Test
  LEGACY_SAMPLE = {
    "film_grain" => 0.5,
    "sepia" => 0.3,
    "film_scratches" => 0.4,
    "soft_focus" => 0.6,
    "teal_and_orange" => 0.4
  }.freeze

  def test_legacy_pub_sample_recipe_remains_reachable
    unknown = LEGACY_SAMPLE.keys - RECIPE_ALLOWED
    assert_empty unknown, "legacy sample recipe keys must remain in RECIPE_ALLOWED: #{unknown.join(', ')}"
  end
end
