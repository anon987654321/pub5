# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../lib/voice/speech"

class SpeechContractSpec < Minitest::Test
  def test_house_eq_is_warm_scooped_and_open_without_extra_effects
    chain = Master::Voice::Policy.post_chain

    assert_includes chain, "lowshelf=f=125:g=1.2"
    assert_includes chain, "equalizer=f=1250:t=q:w=1.0:g=-1.6"
    assert_includes chain, "highshelf=f=8500:g=1.5"
    assert_includes chain, "alimiter=limit=0.98"
    refute_includes chain, "tremolo"
    refute_includes chain, "echo="
  end

  def test_clean_text_preserves_spoken_content_while_removing_markup
    cleaned = Master::Voice::Speech.clean_text("hello `code` https://example.com ```ruby\nx\n```")
    # A URL is spoken as its host: nobody wants the scheme and path read aloud.
    assert_includes cleaned, "example.com"
    refute_includes cleaned, "https://"
    assert_includes cleaned, "code"
    assert_includes cleaned, "x"
    refute_includes cleaned, "```"
    refute_includes cleaned, "`"
  end

  def test_chunks_keep_normal_sentences_intact
    chunks = Master::Voice::Speech.chunks(
      "One sentence. Two sentence. Three sentence.",
      max: 8,
    )
    assert_equal ["One sentence.", "Two sentence.", "Three sentence."], chunks
  end

  def test_chunks_do_not_split_an_oversized_sentence_at_arbitrary_words
    sentence = "This is one deliberately long sentence that remains one thought."
    chunks = Master::Voice::Speech.chunks(sentence, max: 16)
    assert_equal [sentence], chunks
  end

  def test_voice_and_style_are_env_configurable
    old_voice = ENV["MASTER_TTS_VOICE"]
    old_style = ENV["MASTER_TTS_STYLE"]
    ENV["MASTER_TTS_VOICE"] = "finn"
    ENV["MASTER_TTS_STYLE"] = "calm"
    assert_equal :finn, Master::Voice::Speech.default_voice
    assert_equal :calm, Master::Voice::Speech.default_style
  ensure
    ENV["MASTER_TTS_VOICE"] = old_voice
    ENV["MASTER_TTS_STYLE"] = old_style
  end

  def test_house_delivery_defaults_to_eager_and_is_shared_with_fallback_policy
    previous_style = ENV.delete("MASTER_TTS_STYLE")
    previous_profile = ENV.delete("MASTER_TTS_PROFILE")
    Master::Voice::Policy.reload!

    assert_equal :eager, Master::Voice::Speech.default_style
    assert_equal({ rate: "+6%", pitch: "+6Hz" },
                 Master::Voice::Speech.style_config_for(:christopher, :eager))
    assert_equal "+6%", Master::Voice::Policy.default_rate
    assert_equal "+6Hz", Master::Voice::Policy.default_pitch
    assert_equal "+6%", Master::Voice::Transcendent.supportive_rate(
      "Hello there.", :eager, { "warmth" => 0.5, "depth" => 0.5 }
    )
    assert_equal "+8Hz", Master::Voice::Transcendent.supportive_pitch(
      "Hello there.", :eager, { "depth" => 0.5 }
    )
  ensure
    ENV["MASTER_TTS_STYLE"] = previous_style if previous_style
    ENV["MASTER_TTS_PROFILE"] = previous_profile if previous_profile
    Master::Voice::Policy.reload!
  end

  def test_transcendent_engine_chain_can_be_overridden
    old = ENV["MASTER_TTS_ENGINE_CHAIN"]
    ENV["MASTER_TTS_ENGINE_CHAIN"] = "edge,say"

    cfg = Master::Voice::Transcendent.load_config
    assert_equal "edge,say", cfg["engine_chain"]
  ensure
    old.nil? ? ENV.delete("MASTER_TTS_ENGINE_CHAIN") : ENV["MASTER_TTS_ENGINE_CHAIN"] = old
  end

  def test_native_say_fallback_has_no_host_default_voice_path
    refute Master::Voice::Engines::MACOS_VOICE_FALLBACKS.key?(:jenny)
    assert_equal "Alex", Master::Voice::Engines::MACOS_VOICE_FALLBACKS.fetch(:andrew)
    refute Master::Voice::Engines::MACOS_VOICE_FALLBACKS.key?(:pernille)
    refute Master::Voice::Engines::MACOS_VOICE_FALLBACKS.key?(:finn)
  end
end
