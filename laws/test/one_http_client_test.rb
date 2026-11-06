# frozen_string_literal: true
require "minitest/autorun"
require "tmpdir"
require_relative "../detectors/one_http_client"
class OneHttpClientTest < Minitest::Test
  def test_finds_direct_http_and_ignores_the_core_client
    Dir.mktmpdir do |root|
      File.write(File.join(root, "bad.rb"), "Net::HTTP.get(URI(\"https://example.com\"))\n")
      File.write(File.join(root, "good.rb"), "Pub5::Core::HttpClient.new(allowed_hosts: [\"example.com\"])\n")
      assert_equal ["bad.rb"], Pub5::Laws::OneHttpClient.findings(root).map(&:first)
    end
  end
end
