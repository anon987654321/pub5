# frozen_string_literal: true

require "test_helper"

class PollComicStripJobTest < ActiveJob::TestCase
  test "stores only safe provider image URLs" do
    user = User.create!(
      email_address: "poll-#{SecureRandom.hex(6)}@example.test",
      password: "password123"
    )
    comic_strip = user.comic_strips.create!(
      prompt: "A test comic",
      style: "comic",
      status: "processing",
      prediction_id: "prediction_123",
      provider_consent_at: Time.current
    )
    service = Minitest::Mock.new
    service.expect(
      :get_prediction,
      {
        "status" => "succeeded",
        "output" => [
          "https://replicate.delivery/panel.png",
          "https://example.test/not-provider.png"
        ]
      },
      "prediction_123"
    )

    ReplicateService.stub(:new, service) do
      PollComicStripJob.perform_now(comic_strip.id)
    end

    service.verify
    assert_equal "completed", comic_strip.reload.status
    assert_equal ["https://replicate.delivery/panel.png"], comic_strip.image_urls
  end
end
