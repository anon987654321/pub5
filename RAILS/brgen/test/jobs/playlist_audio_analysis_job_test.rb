# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "shared/subprocess"

class PlaylistAudioAnalysisJobTest < ActiveSupport::TestCase
  test "waveform represents silence and actual signal rather than a track identifier" do
    skip "ffmpeg and ffprobe required" unless %w[ffmpeg ffprobe].all? { |command| Shared::Subprocess.on_path?(command) }

    Dir.mktmpdir do |dir|
      path = File.join(dir, "sample.wav")
      _, _, status = Shared::Subprocess.capture3(
        "ffmpeg", "-nostdin", "-v", "error", "-f", "lavfi",
        "-i", "aevalsrc=if(lt(t\\,0.5)\\,0\\,0.5*sin(2*PI*440*t)):s=44100:d=1",
        "-y", path, timeout: 10
      )
      assert status.success?
      result = Playlist::AudioAnalysisJob.analyze(path)
      assert_in_delta 1.0, result.fetch(:duration), 0.01
      peaks = result.fetch(:peaks)
      assert peaks.size.between?(90, 96)
      assert_operator peaks.first(40).max, :<, 0.01
      assert_operator peaks.last(40).max, :>, 0.4
    end
  end
end
