# frozen_string_literal: true

require_relative "../test_helper"

class TestVoiceOneSpeaker < Minitest::Test
  Speech = Master::Voice::Speech
  Playback = Master::Voice::Playback

  def test_global_os_fallback_stays_off_outside_the_mapped_mac_path
    assert_equal false, Master::Voice::Policy.data["os_voice_fallback"]

    Speech.stub(:macos_host?, false) do
      refute Speech.os_voice_fallback?(voice: :christopher)
      refute Speech.os_voice_fallback?(voice: :pernille)
    end
  end

  def test_mac_fallback_is_limited_to_the_explicitly_mapped_voice
    Speech.stub(:macos_host?, true) do
      assert Speech.os_voice_fallback?(voice: :christopher)
      assert Speech.os_voice_fallback?(voice: :andrew)
      refute Speech.os_voice_fallback?(voice: :pernille)
      refute Speech.os_voice_fallback?(voice: :finn)
    end
  end

  def test_failed_edge_uses_the_mapped_mac_voice_even_when_voice_is_locked
    Speech.instance_variable_set(:@last_error, "Edge endpoint answered nothing")
    Speech.stub(:macos_host?, true) do
      Speech.stub(:available?, true) do
        Speech.stub(:edge_tts_available?, true) do
          Speech.stub(:synthesize_edge, nil) do
            Speech.stub(:synthesize_say, "/tmp/m_tts_mapped_mac.aiff") do
              assert_equal "/tmp/m_tts_mapped_mac.aiff",
                           Speech.synthesize("a sentence that edge fails", voice: :christopher, voice_locked: true)
              assert_equal "say", Speech.last_engine
              assert_nil Speech.last_error
            end
          end
        end
      end
    end
  ensure
    Speech.instance_variable_set(:@last_engine, nil)
  end

  def test_a_failed_edge_sentence_stays_silent_on_unmapped_hosts
    refuses = ->(_text) { flunk "an unmapped host voice must not be asked" }

    Speech.stub(:macos_host?, false) do
      Speech.stub(:available?, true) do
        Speech.stub(:edge_tts_available?, true) do
          Speech.stub(:synthesize_edge, nil) do
            Speech.stub(:synthesize_say, refuses) do
              assert_nil Speech.synthesize("a sentence that edge fails", voice: :christopher, voice_locked: true)
            end
          end
        end
      end
    end
  end
end
