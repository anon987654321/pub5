# frozen_string_literal: true

# Chrome 158 refuses Storage.clearDataForOrigin with origin "*", which
# Capybara 3.40 (the latest release) sends from ChromeDriver#reset! after every
# system test. Clear every cookie browser-wide and each origin a test visited.
require "uri"
require "capybara/selenium/driver"
require "capybara/selenium/driver_specializations/chrome_driver"

module Pub5ChromeStorageReset
  def visit(url)
    origin = URI.parse(url.to_s)
    (@pub5_origins ||= Set.new) << "#{origin.scheme}://#{origin.host}:#{origin.port}" if origin.host
    super
  end

  private

  def execute_cdp(cmd, params = {})
    return super unless cmd == "Storage.clearDataForOrigin" && params[:origin] == "*"

    super("Network.clearBrowserCookies")
    Array(@pub5_origins).each { |origin| super(cmd, params.merge(origin:)) }
    @pub5_origins&.clear
  end
end

Capybara::Selenium::Driver::ChromeDriver.prepend(Pub5ChromeStorageReset)
