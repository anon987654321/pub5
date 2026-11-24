# frozen_string_literal: true

require "test_helper"

# The Name/Updated sort chips and the category chips set no min-height, so
# both were well under the 44px tap floor (--tap-min).
class StylesheetTapTargetsTest < ActiveSupport::TestCase
  SOURCE = Rails.root.join("app/assets/stylesheets/application.scss").read

  test "sort and category chips meet the tap floor" do
    [ "nav.sort-order a", ".category-list .chip" ].each do |selector|
      # The rules sit inside @layer components, so they are indented.
      block = SOURCE[/^([ \t]*)#{Regexp.escape(selector)} \{\n(.*?)\n\1\}/m, 2]
      assert block, "no #{selector} rule"
      assert_includes block, "min-height: var(--tap-min);", selector
    end
  end
end
