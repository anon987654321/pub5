# frozen_string_literal: true

require_relative "test_helper"

# Where a sound request goes. Every sink is stubbed: nothing here reaches a
# speaker, a file under ~, or dilla.
class TestMusicSynthIntent < Minitest::Test
  INTENT = Master::Io::MediaIntent

  def with_audio_file
    Dir.mktmpdir("master-audio-player") do |dir|
      path = File.join(dir, "track.wav")
      File.binwrite(path, "RIFF")
      yield path
    end
  end

  def test_file_playback_uses_the_sox_play_command
    with_audio_file do |path|
      available = { "play" => "/opt/homebrew/bin/play" }
      argv = nil
      Master::Io::Exec.stub(:which, ->(name, prefer:) { available[name] }) do
        Process.stub(:spawn, ->(*args, **_options) { argv = args; 4242 }) do
          Process.stub(:detach, ->(_pid) { nil }) do
            assert_equal 4242, Master::Music::Synth.play(path)
          end
        end
      end

      assert_equal ["/opt/homebrew/bin/play", "-q", path], argv.drop(1)
    end
  end

  def test_file_playback_falls_back_when_the_first_player_cannot_start
    with_audio_file do |path|
      available = { "afplay" => "/usr/bin/afplay", "play" => "/opt/homebrew/bin/play" }
      attempts = []
      Master::Io::Exec.stub(:which, ->(name, prefer:) { available[name] }) do
        Process.stub(:spawn, lambda { |*args, **_options|
          attempts << args
          raise Errno::ENOENT if attempts.one?

          5150
        }) do
          Process.stub(:detach, ->(_pid) { nil }) do
            assert_equal 5150, Master::Music::Synth.play(path)
          end
        end
      end

      assert_equal 2, attempts.size
      assert_equal "/usr/bin/afplay", attempts.first[1]
      assert_equal ["/opt/homebrew/bin/play", "-q", path], attempts.last.drop(1)
    end
  end

  def test_file_playback_names_all_supported_players_when_none_exist
    with_audio_file do |path|
      Master::Io::Exec.stub(:which, ->(_name, prefer:) { nil }) do
        error = assert_raises(Master::Music::Synth::NoPlayerError) do
          Master::Music::Synth.play(path)
        end
        assert_match(/afplay, play, ffplay, mpv, aucat/, error.message)
      end
    end
  end

  def test_render_writes_the_waveform_to_a_file
    seen = nil
    captured_path = nil
    Master::Music::Synth.stub(:render, ->(shape:, hz:, destination:) do
      seen = [shape, hz]
      captured_path = destination
      destination
    end) do
      result = INTENT.dispatch("render a square wave")
      assert result.ok?
      assert_equal [:square, 440.0], seen
      assert_equal captured_path, result.value[:path]
    end
  end

  def test_deep_tone_uses_low_pitch
    seen = nil
    Master::Music::Synth.stub(:render, ->(shape:, hz:, destination:) do
      seen = hz
      destination
    end) do
      INTENT.dispatch("make a deep sine wave")
    end
    assert_equal 110.0, seen
  end

  # "play" is the speakers: the tone streams live and no file is written.
  def test_play_streams_the_tone_live_and_writes_nothing
    played = nil
    rendered = false
    Master::Music::Realtime.stub(:play, ->(shape:, hz:, seconds:) { played = [shape, hz, seconds] }) do
      Master::Music::Synth.stub(:render, ->(**) { rendered = true }) do
        result = INTENT.dispatch("play me a sine wave")
        assert result.ok?
        assert_equal :synth_live, result.value[:media]
      end
    end
    assert_equal [:sine, 440.0, INTENT::LIVE_TONE_SECONDS], played
    refute rendered, "a played tone must not also be written to disk"
  end

  def test_a_missing_player_is_named_with_the_fix
    no_player = ->(**) { raise Master::Music::AudioSink::NoPlayerError, "no streaming player found" }
    Master::Music::Realtime.stub(:play, no_player) do
      result = INTENT.dispatch("play a saw wave on my speakers")
      refute result.ok?
      assert_match(/brew install sox/, result.message)
    end
  end

  def test_cant_hear_is_a_live_audio_diagnostic_not_a_chat_claim
    assert INTENT.handles?("i can't hear anything")
    INTENT.instance_variable_set(:@player_pid, nil)
    result = INTENT.dispatch("i can't hear anything")
    assert result.ok?
    assert_equal :dilla_audio_diagnostic, result.value[:media]
    assert_match(/nothing is playing/, result.value[:output])

    child = Process.spawn(RbConfig.ruby, "-e", "sleep 30")
    INTENT.instance_variable_set(:@player_pid, child)
    playing = INTENT.dispatch("i can't hear anything")
    assert_match(/player process running \\(pid #{child}\\)/, playing.value[:output])
    assert_match(/MASTER can verify the player process/, playing.value[:output])
  ensure
    INTENT.stop_player
    INTENT.instance_variable_set(:@player_pid, nil)
  end

  # "play it" after a render plays that render, whatever else the sentence says.
  def test_play_it_plays_the_last_rendered_file
    played = nil
    INTENT.stub(:last_media, "/home/op/master-sine-20260924T120000Z.wav") do
      Master::Music::Synth.stub(:play, ->(path) { played = path && 4242 }) do
        result = INTENT.dispatch("play it on my sound card")
        assert result.ok?
        assert_equal :playback, result.value[:media]
        assert_match(/pid 4242/, result.value[:output])
      end
    end
    assert_equal 4242, played
  end

  def test_last_media_is_the_newest_render
    Dir.mktmpdir do |dir|
      old = File.join(dir, "master-sine-20260101T000000Z.wav")
      new = File.join(dir, "dilla-20260924T120000Z.wav")
      File.write(old, "")
      File.write(new, "")
      File.write(File.join(dir, "notes.txt"), "")
      File.utime(Time.now - 60, Time.now - 60, old)
      assert_equal new, INTENT.last_media(dir)
    end
  end

  # A sentence addressed to the music renders a progression and plays it.
  def test_music_sentences_render_a_progression_and_play_it
    sentences = ["play", "play some music", "improvise", "keep playing", "play me something with moog patches", "play a moog bass",
                 "play me a chord progression with a few different moog patches"]
    listing = "Progressions:\n   0  Cm9 Fm9\n   1  Dm7 G7\n\nDrum patterns: a, b\nGroove profiles: x, y\n"
    Dir.mktmpdir do |home|
      saved = ENV.fetch("XDG_DATA_HOME", nil)
      ENV["XDG_DATA_HOME"] = home
      sentences.each do |sentence|
        sent = []
        runner = lambda do |root:, tool:, arg:, env: {}|
          sent << [tool, arg]
          arg == "--list" ? Master::Result.ok(listing) : Master::Result.ok("wrote")
        end
        Master::Io::ScriptDispatch.stub(:run, runner) do
          Master::Music::Synth.stub(:play, 4242) do
            assert INTENT.handles?(sentence), sentence
            result = INTENT.dispatch(sentence)
            assert result.ok?, sentence
            assert_equal :dilla_live, result.value[:media], sentence
          end
        end
        assert_equal "--list", sent.first.last, sentence
        assert_includes sent.last.last, "--progression", sentence
        INTENT.instance_variable_set(:@player_pid, nil)
      end
    ensure
      saved ? ENV["XDG_DATA_HOME"] = saved : ENV.delete("XDG_DATA_HOME")
    end
  end

  def test_explicit_dilla_files_and_soundcard_mean_live_music
    sentence = "play music dilla.rb on my local sound card"
    listing = "Progressions:\n   0  Cm9 Fm9\n\nDrum patterns: a\nGroove profiles: x\n"
    Dir.mktmpdir do |home|
      saved = ENV.fetch("XDG_DATA_HOME", nil)
      ENV["XDG_DATA_HOME"] = home
      runner = ->(root:, tool:, arg:, env: {}) { arg == "--list" ? Master::Result.ok(listing) : Master::Result.ok("wrote") }
      Master::Io::ScriptDispatch.stub(:run, runner) do
        Master::Music::Synth.stub(:play, 4242) do
          assert INTENT.handles?(sentence)
          result = INTENT.dispatch(sentence)
          assert result.ok?
          assert_equal :dilla_live, result.value[:media]
        end
      end
    ensure
      INTENT.instance_variable_set(:@player_pid, nil)
      saved ? ENV["XDG_DATA_HOME"] = saved : ENV.delete("XDG_DATA_HOME")
    end
  end

  def test_code_talk_is_not_music
    ["open the patch in the editor", "turn the lead generator into a service", "fix the filter in search",
     "what is a moog"].each do |sentence|
      refute INTENT.live_synth?(sentence), sentence
    end
  end
end
