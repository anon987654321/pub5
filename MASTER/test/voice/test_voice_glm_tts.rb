# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../lib/voice/engines"

class TestVoiceGlmTts < Minitest::Test
  Engines = Master::Voice::Engines

  def test_glm_speed_scales_and_clamps_to_the_api_range
    cfg = { "glm_speed" => 1.0 }
    assert_in_delta 1.06, Engines.glm_speed(cfg, "+6%"), 0.0001
    assert_in_delta 0.9, Engines.glm_speed(cfg, "-10%"), 0.0001
    assert_in_delta 0.5, Engines.glm_speed(cfg, "-80%"), 0.0001
    assert_in_delta 2.0, Engines.glm_speed({ "glm_speed" => 1.9 }, "+10%"), 0.0001
    assert_in_delta 1.0, Engines.glm_speed({}, nil), 0.0001
  end

  def test_glm_text_chunks_keeps_short_text_whole
    assert_equal ["Short."], Engines.glm_text_chunks("Short.")
    assert_empty Engines.glm_text_chunks("   ")
  end

  def test_glm_text_chunks_splits_long_text_on_sentence_boundaries
    sentence = "a" * 500 + ". "
    chunks = Engines.glm_text_chunks((sentence * 3).strip)

    assert_equal 2, chunks.length
    chunks.each do |chunk|
      assert_operator chunk.length, :<=, Engines::GLM_TTS_REQUEST_CEILING
    end
  end

  def test_glm_text_chunks_never_cuts_inside_a_sentence
    chunks = Engines.glm_text_chunks("b" * 1100)

    assert_equal 1, chunks.length
    # An oversized single sentence stays whole: the bridge refuses it, the
    # engine reports failure, and the chain falls through. Never a mid-cut.
    assert_operator chunks.first.length, :>, Engines::GLM_TTS_REQUEST_CEILING
  end

  def test_glm_tts_requires_the_bridge_script
    Engines.stub(:glm_tts_script, "/nonexistent/zai-tts") do
      refute Engines.glm_tts_ready?
    end
  end

  def test_glm_tts_ready_when_script_and_credential_exist
    Engines.stub(:glm_tts_script, __FILE__) do
      Engines.stub(:glm_tts_config?, true) do
        assert Engines.glm_tts_ready?
      end
    end
  end

  def test_master_tts_no_glm_disables_the_engine
    ENV["MASTER_TTS_NO_GLM"] = "1"
    Engines.stub(:glm_tts_script, __FILE__) do
      Engines.stub(:glm_tts_config?, true) do
        refute Engines.glm_tts_ready?
      end
    end
  ensure
    ENV.delete("MASTER_TTS_NO_GLM")
  end

  def test_unmapped_voice_fails_closed_without_a_network_call
    called = false
    Engines.stub(:run_zai_tts, ->(*) { called = true; true }) do
      refute Engines.synth_glm_tts(
        "Hei, verden.", "/tmp/glm_closed.mp3",
        { "glm_voice_map" => { "christopher" => "jam" } }, {},
        voice: :pernille, rate: "+0%",
      )
    end
    refute called, "an unmapped voice must fail before the bridge is invoked"
  end

  def test_mapped_voice_synthesizes_once_and_converts
    calls = []
    Engines.stub(:run_zai_tts, lambda { |_voice, _speed, out_path, _text|
      File.write(out_path, "wav")
      calls << out_path
      true
    }) do
      Engines.stub(:convert_to_mp3, lambda { |_wav, mp3|
        File.write(mp3, "mp3")
        true
      }) do
        assert Engines.synth_glm_tts(
          "Hello from the hosted lane.", "/tmp/glm_one.mp3",
          { "glm_voice_map" => { "christopher" => "jam" } }, {},
          voice: :christopher, rate: "+6%",
        )
      end
    end
    assert_equal 1, calls.length
  ensure
    File.delete("/tmp/glm_one.mp3") if File.exist?("/tmp/glm_one.mp3")
    clear_glm_tmp_dir
  end

  def test_partial_bridge_failure_drops_the_whole_utterance
    sentence = "a" * 500 + ". "
    text = (sentence * 3).strip # two chunks at the 1024-character ceiling
    calls = 0
    Engines.stub(:run_zai_tts, lambda { |_voice, _speed, out_path, _text|
      calls += 1
      if calls == 1
        File.write(out_path, "wav")
        true
      else
        false
      end
    }) do
      refute Engines.synth_glm_tts(
        text, "/tmp/glm_multi.mp3",
        { "glm_voice_map" => { "christopher" => "jam" } }, {},
        voice: :christopher, rate: "+0%",
      )
    end
    assert_equal 2, calls
  ensure
    clear_glm_tmp_dir
  end

  private

  # Part files land in the runtime dir (same convention as .master/melodic);
  # a test leaves nothing behind there.
  def clear_glm_tmp_dir
    Dir.children(File.join(Master::ROOT, ".master", "glm_tts")).each do |name|
      File.delete(File.join(Master::ROOT, ".master", "glm_tts", name))
    rescue StandardError
      nil
    end
  end
end
