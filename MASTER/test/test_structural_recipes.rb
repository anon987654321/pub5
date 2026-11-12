# frozen_string_literal: true

require_relative "test_helper"

class TestStructuralRecipes < Minitest::Test
  def setup
    @catalogue = Master::Fix::StructuralRecipes.new(repo_root: Master::REPO_ROOT)
  end

  def test_catalogue_is_allowlisted_and_names_the_declared_proof
    rows = @catalogue.list

    assert_equal ["slugged_vertical_base"], rows.map(&:first)
    recipe = @catalogue.fetch("slugged_vertical_base")
    assert_equal "RAILS", recipe.tree
    assert_equal "merge", recipe.operation
    assert_equal 5, recipe.plan.writes.size
    assert_equal [], recipe.plan.deletes
    assert_equal ["test/controllers/vertical_base_controller_test.rb"],
                 recipe.proofs.map { |proof| proof.fetch("path") }
  end

  def test_current_tree_is_an_idempotent_noop_and_preview_writes_nothing
    recipe = @catalogue.fetch("slugged_vertical_base")
    before = recipe.plan.paths.to_h do |path|
      [path, File.binread(File.join(Master::REPO_ROOT, path))]
    end

    result = @catalogue.preview(recipe.name)

    assert result.ok?, -> { result.message }
    value = result.value!
    assert value.fetch(:already_applied)
    assert_empty value.fetch(:diff)
    assert_equal recipe.plan.paths.sort, value.fetch(:paths).sort
    assert_equal before, recipe.plan.paths.to_h { |path| [path, File.binread(File.join(Master::REPO_ROOT, path))] }
  end

  def test_fix_can_list_recipes_without_a_model_lane
    output = Master::CLI::CommandRegistry.dispatch_structural_recipe("--list-recipes", deliberation: nil)

    assert_includes output, "slugged_vertical_base"
    assert_includes output, "PlaylistHelper"
  end

  def test_recipe_requires_an_explicit_preview_or_apply_mode
    output = Master::CLI::CommandRegistry.dispatch_structural_recipe(
      "--recipe slugged_vertical_base", deliberation: nil
    )

    assert_includes output, "usage:"
    assert_includes output, "--dry-run"
    assert_includes output, "--apply"
  end

  def test_unknown_recipe_is_refused_without_mutation
    output = Master::CLI::CommandRegistry.dispatch_structural_recipe(
      "--recipe not_a_recipe --dry-run", deliberation: nil
    )

    assert_includes output, "REFUSED"
    assert_includes output, "unknown structural recipe"
  end
end
