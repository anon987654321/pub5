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

  def test_url_policy_rejects_http_embedded_credentials_and_nonstandard_ports
    agent = Master::Tools::BrowserAgent.allocate
    assert_raises(Master::Tools::BrowserAgent::Error) { agent.send(:public_uri!, "http://example.com") }
    assert_raises(Master::Tools::BrowserAgent::Error) { agent.send(:public_uri!, "https://user:secret@example.com") }
    assert_raises(Master::Tools::BrowserAgent::Error) { agent.send(:public_uri!, "https://example.com:8443") }
  end

  def test_sensitive_url_query_values_are_redacted_before_model_observation
    agent = Master::Tools::BrowserAgent.allocate
    safe = agent.send(:redact_url, "https://example.com/path?tab=two&code=123&session=abc#fragment")
    assert_equal "https://example.com/path?tab=two&code=%5Bredacted%5D&session=%5Bredacted%5D", safe
  end
end
