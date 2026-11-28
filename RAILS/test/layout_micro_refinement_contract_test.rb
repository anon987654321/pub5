# frozen_string_literal: true

require "minitest/autorun"

class LayoutMicroRefinementContractTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  LAYOUTS = %w[
    amber/app/views/layouts/application.html.erb
    brgen/app/views/layouts/application.html.erb
    bsdports/app/views/layouts/application.html.erb
  ].freeze

  def test_browser_layouts_name_the_shared_layout_contract_not_an_experiment
    LAYOUTS.each do |relative|
      source = File.read(File.expand_path(relative, ROOT), encoding: "UTF-8")
      assert_includes source, 'data-layout-contract="shared-layout"'
      refute_includes source, 'data-layout-pass="micro-320"'
    end
  end
end
