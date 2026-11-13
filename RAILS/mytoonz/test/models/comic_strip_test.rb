# frozen_string_literal: true

require "test_helper"

class ComicStripTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(
      email_address: "toon-#{SecureRandom.hex(6)}@example.test",
      password: "password123"
    )
  end

  test "requires a prompt" do
    strip = build_strip(prompt: " ")

    assert_not strip.valid?
    assert_includes strip.errors.attribute_names, :prompt
  end

  test "rejects prompts longer than the provider limit" do
    strip = build_strip(prompt: "x" * 4_001)

    assert_not strip.valid?
    assert_includes strip.errors.attribute_names, :prompt
  end

  test "accepts only declared styles and states" do
    assert build_strip(style: "manga").valid?
    assert_not build_strip(style: "unknown").valid?
    assert_not build_strip(status: "queued_forever").valid?
  end

  test "only exposes Replicate delivery images to the view" do
    strip = build_strip(image_urls: [
      "https://replicate.delivery/panel.png",
      "http://replicate.delivery/insecure.png",
      "https://example.test/remote.png"
    ])

    assert_equal ["https://replicate.delivery/panel.png"], strip.safe_image_urls
  end

  private

  def build_strip(overrides = {})
    ComicStrip.new({
      user: @user,
      prompt: "A friendly comic about a rainy Bergen afternoon.",
      style: "comic",
      status: "pending"
    }.merge(overrides))
  end
end
