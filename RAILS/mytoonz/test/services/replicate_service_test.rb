# frozen_string_literal: true

require "test_helper"

class ReplicateServiceTest < ActiveSupport::TestCase
  test "does not attempt generation without a provider token" do
    result = ReplicateService.new(api_token: nil).generate_comic_strip(prompt: "A test")

    assert_equal "REPLICATE_API_TOKEN not set", result.fetch("error")
  end

  test "rejects malformed prediction IDs before making a request" do
    result = ReplicateService.new(api_token: "not-a-real-token").get_prediction("../admin")

    assert_equal "Invalid prediction ID", result.fetch("error")
  end

  test "accepts only HTTPS images from Replicate delivery hosts" do
    assert ReplicateService.safe_output_url?("https://replicate.delivery/panel.png")
    assert ReplicateService.safe_output_url?("https://pbxt.replicate.delivery/panel.png")
    refute ReplicateService.safe_output_url?("http://replicate.delivery/panel.png")
    refute ReplicateService.safe_output_url?("https://example.test/panel.png")
  end
end
