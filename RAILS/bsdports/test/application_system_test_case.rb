# frozen_string_literal: true

require "test_helper"
require_relative "../../__shared/test/capybara_falcon"
require_relative "../../__shared/test/capybara_chrome_reset"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ]
end
