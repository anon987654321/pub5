# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../master/tools/browser_agent"

class BrowserAgentTest < Minitest::Test
  def test_only_public_ipv4_addresses_are_accepted
    assert Master::Tools::BrowserAgent.public_ipv4?("93.184.216.34")
    refute Master::Tools::BrowserAgent.public_ipv4?("127.0.0.1")
    refute Master::Tools::BrowserAgent.public_ipv4?("10.0.0.4")
    refute Master::Tools::BrowserAgent.public_ipv4?("169.254.169.254")
    refute Master::Tools::BrowserAgent.public_ipv4?("192.168.1.5")
    refute Master::Tools::BrowserAgent.public_ipv4?("224.0.0.1")
    refute Master::Tools::BrowserAgent.public_ipv4?("::1")
  end

  def test_url_policy_rejects_http_and_embedded_credentials
    agent = Master::Tools::BrowserAgent.allocate
    assert_raises(Master::Tools::BrowserAgent::Error) { agent.send(:public_uri!, "http://example.com") }
    assert_raises(Master::Tools::BrowserAgent::Error) { agent.send(:public_uri!, "https://user:secret@example.com") }
  end
end
