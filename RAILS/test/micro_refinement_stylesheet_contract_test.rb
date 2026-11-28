# frozen_string_literal: true

require "minitest/autorun"

class MicroRefinementStylesheetContractTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  STACKS = %w[
    __shared/app/assets/stylesheets/_stack.scss
    __shared/app/assets/stylesheets/_stack_brgen.scss
  ].freeze
  SUPPORTED_STACK_IMPORTS = %w[layout_primitives typography].freeze
  EXPERIMENTAL_SHEETS = %w[
    layout_micro_refinements
    surface_micro_refinements
    surface_micro_refinements_two
  ].freeze
  LAYOUTS = %w[
    amber/app/views/layouts/application.html.erb
    brgen/app/views/layouts/application.html.erb
    bsdports/app/views/layouts/application.html.erb
  ].freeze

  def test_browser_layouts_name_the_shared_layout_contract_not_an_experiment
    LAYOUTS.each do |relative|
      source = File.read(File.join(ROOT, relative), encoding: "UTF-8")
      assert_includes source, 'data-layout-contract="shared-layout"'
      refute_includes source, 'data-layout-pass="micro-320"'
    end
  end

  def test_unvalidated_experiment_sheets_are_absent_from_the_active_asset_tree
    EXPERIMENTAL_SHEETS.each do |sheet|
      path = File.join(ROOT, "__shared/app/assets/stylesheets/_#{sheet}.scss")
      refute File.exist?(path), "#{sheet} must not become an active stylesheet without rendered review"
    end
  end

  def test_production_stacks_load_supported_styles_and_exclude_experiments
    STACKS.each do |relative|
      source = File.read(File.join(ROOT, relative), encoding: "UTF-8")
      SUPPORTED_STACK_IMPORTS.each do |sheet|
        assert_includes source, %(@forward "#{sheet}";)
      end
      EXPERIMENTAL_SHEETS.each do |sheet|
        refute_includes source, %(@forward "#{sheet}";),
                        "#{sheet} must stay out of production until rendered review approves it"
      end
    end
  end
end
