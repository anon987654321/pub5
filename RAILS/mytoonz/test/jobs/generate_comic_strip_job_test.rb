# frozen_string_literal: true

require "test_helper"

class GenerateComicStripJobTest < ActiveJob::TestCase
  setup do
    user = User.create!(
      email_address: "job-#{SecureRandom.hex(6)}@example.test",
      password: "password123"
    )
    @comic_strip = user.comic_strips.create!(
      prompt: "A test comic",
      style: "comic",
      status: "pending"
    )
  end

  test "does not call the provider without recorded consent" do
    service = Minitest::Mock.new

    ReplicateService.stub(:new, service) do
      GenerateComicStripJob.perform_now(@comic_strip.id)
    end

    service.verify
    assert_equal "failed", @comic_strip.reload.status
  end

  test "starts polling after a consented prediction is accepted" do
    @comic_strip.update!(provider_consent_at: Time.current)
    service = Minitest::Mock.new
    service.expect(
      :generate_comic_strip,
      { "id" => "prediction_123" },
      prompt: @comic_strip.prompt,
      style: @comic_strip.style
    )

    ReplicateService.stub(:new, service) do
      assert_enqueued_with(job: PollComicStripJob, args: [@comic_strip.id]) do
        GenerateComicStripJob.perform_now(@comic_strip.id)
      end
    end

    service.verify
    assert_equal "processing", @comic_strip.reload.status
    assert_equal "prediction_123", @comic_strip.prediction_id
  end
end
