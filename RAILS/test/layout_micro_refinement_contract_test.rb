# frozen_string_literal: true

require "minitest/autorun"

class LayoutMicroRefinementContractTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  LAYOUTS = %w[
    amber/app/views/layouts/application.html.erb
    brgen/app/views/layouts/application.html.erb
    bsdports/app/views/layouts/application.html.erb
  ].freeze

  SHARED_STACKS = %w[
    __shared/app/assets/stylesheets/_stack.scss
    __shared/app/assets/stylesheets/_stack_brgen.scss
  ].freeze

  EXPERIMENTAL_SHEETS = %w[
    layout_micro_refinements
    surface_micro_refinements
    surface_micro_refinements_two
  ].freeze

  def test_browser_layouts_name_the_shared_layout_contract_not_an_experiment
    LAYOUTS.each do |relative|
      source = File.read(File.expand_path(relative, ROOT), encoding: "UTF-8")
      assert_includes source, 'data-layout-contract="shared-layout"'
      refute_includes source, 'data-layout-pass="micro-320"'
    end
  end

  def test_production_stacks_do_not_load_unvalidated_refinement_sheets
    SHARED_STACKS.each do |relative|
      source = File.read(File.expand_path(relative, ROOT), encoding: "UTF-8")
      EXPERIMENTAL_SHEETS.each do |sheet|
        refute_includes source, %(@forward "#{sheet}";),
                        "#{sheet} must stay out of production until rendered review approves it"
      end
      assert_includes source, '@forward "layout_primitives";'
      assert_includes source, '@forward "typography";'
    end
  end

  def test_all_unvalidated_experiment_sheets_are_absent_from_the_active_asset_tree
    EXPERIMENTAL_SHEETS.each do |sheet|
      path = File.join(ROOT, "__shared/app/assets/stylesheets/_#{sheet}.scss")
      refute File.exist?(path), "#{sheet} must not become an active stylesheet without rendered review"
    end
  end
end
