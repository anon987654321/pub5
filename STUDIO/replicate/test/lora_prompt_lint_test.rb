# frozen_string_literal: true

require_relative "minitest_helper"
require "tmpdir"
require_relative "../../lora/idea_picture"

# Synthetic subject authorization: real consent is tested separately.
Studio::Lora::Consent.define_singleton_method(:require!) { |**| { "valid" => true } }

# The backfiring-word list sat in Craft with no caller: a prompt could ask for
# "flawless 8k masterpiece" skin and go straight to a paid render. The lint
# now fires before validate_model!, so a self-defeating prompt costs nothing
# and fails with its reasons.
class TestStudioLoraPromptLint < Minitest::Test
  def picture
    Studio::Visual::IdeaPicture.new(subject: "probe", directory: Dir.mktmpdir)
  end

  def test_write_refuses_backfiring_words_before_any_validation
    error = assert_raises(ArgumentError) do
      picture.write("an 8k masterpiece portrait, flawless skin, hyperrealistic", film: false)
    end
    assert_includes error.message, "8k"
    assert_includes error.message, "masterpiece"
    assert_includes error.message, "flawless"
    assert_includes error.message, "hyperrealistic"
  end

  def test_the_refusal_names_the_reason_not_just_the_word
    error = assert_raises(ArgumentError) do
      picture.write("a poreless airbrushed portrait", film: false)
    end
    assert_match(/retouched/, error.message)
  end

  def test_animate_also_lints
    error = assert_raises(ArgumentError) do
      picture.animate("/nonexistent/still.png", "make it an octane render")
    end
    assert_includes error.message, "octane render"
  end

  def test_every_shipped_sitting_passes_its_own_lint
    scenes = (1..10).map { |number| Studio::Lora::Selfie.scene(number) }
    Studio::Lora::Selfie::SUBJECT_SCENES.each_key do |subject|
      scenes.concat((1..6).map { |number| Studio::Lora::Selfie.scene(number, subject:) })
    end
    assert_equal 28, scenes.length
    scenes.each do |body|
      assert_empty Studio::Lora::Craft.backfiring_words(body), body
    end
  end

  def test_clean_prompts_pass
    assert_empty Studio::Lora::Craft.backfiring_words(
      "a quiet portrait by the window, soft daylight, a real half-smile"
    )
  end
end
