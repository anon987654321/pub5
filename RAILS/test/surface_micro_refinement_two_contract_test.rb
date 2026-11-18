# frozen_string_literal: true

require "minitest/autorun"

class SurfaceMicroRefinementTwoContractTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  SHEET = File.join(ROOT, "__shared/app/assets/stylesheets/_surface_micro_refinements_two.scss")
  STACKS = %w[
    __shared/app/assets/stylesheets/_stack.scss
    __shared/app/assets/stylesheets/_stack_brgen.scss
  ].freeze

  def test_experimental_stylesheet_is_absent
    refute File.exist?(SHEET),
           "the unvalidated second surface pass must not remain in the active stylesheet tree"
  end

  def test_production_stacks_do_not_load_the_secondary_experiment
    STACKS.each do |relative|
      source = File.read(File.join(ROOT, relative), encoding: "UTF-8")
      refute_includes source, '@forward "surface_micro_refinements_two";'
    end
  end
end
