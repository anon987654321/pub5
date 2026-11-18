# frozen_string_literal: true

require "minitest/autorun"

class SurfaceMicroRefinementContractTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  SHEET = File.join(ROOT, "__shared/app/assets/stylesheets/_surface_micro_refinements.scss")
  STACKS = %w[
    __shared/app/assets/stylesheets/_stack.scss
    __shared/app/assets/stylesheets/_stack_brgen.scss
  ].freeze

  def test_experimental_stylesheet_is_absent_from_active_asset_tree
    refute File.exist?(SHEET),
           "the unvalidated 288-property experiment must not remain a scanned stylesheet"
  end

  def test_shared_stacks_keep_the_experimental_surface_pass_out_of_production
    STACKS.each do |relative|
      source = File.read(File.join(ROOT, relative), encoding: "UTF-8")
      refute_includes source, '@forward "surface_micro_refinements";'
      refute_includes source, '@forward "surface_micro_refinements_two";'
    end
  end
end
