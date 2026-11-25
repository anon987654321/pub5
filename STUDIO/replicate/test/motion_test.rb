# frozen_string_literal: true

require "open3"
require "tmpdir"
require_relative "minitest_helper"
require_relative "../motion"

class TestStudioReplicateMotion < Minitest::Test
  def ffmpeg?
    @ffmpeg ||= Open3.capture2e("ffmpeg", "-version").last.success?
  rescue Errno::ENOENT
    false
  end

  def test_the_last_frame_of_a_clip_is_a_readable_photograph
    skip "ffmpeg is not on PATH" unless ffmpeg?

    Dir.mktmpdir do |dir|
      clip = File.join(dir, "clip.mp4")
      out = File.join(dir, "frame.jpg")
      Open3.capture2e("ffmpeg", "-v", "error", "-y", "-f", "lavfi",
                      "-i", "testsrc=size=64x64:rate=30:duration=2", "-pix_fmt", "yuv420p", clip)

      Studio::ReplicateClient::Motion.last_frame(clip, out:)

      assert File.file?(out)
      assert_equal 0o600, File.stat(out).mode & 0o777
      assert_equal "\xFF\xD8".b, File.binread(out, 2), "the frame must be a JPEG"
    end
  end

  def test_a_missing_clip_is_refused
    error = assert_raises(ArgumentError) do
      Studio::ReplicateClient::Motion.last_frame("/nowhere/gone.mp4", out: "/tmp/frame.jpg")
    end

    assert_match(/clip not found/, error.message)
  end

  def test_a_file_that_is_not_a_clip_is_refused
    skip "ffmpeg is not on PATH" unless ffmpeg?

    Dir.mktmpdir do |dir|
      fake = File.join(dir, "fake.mp4")
      File.write(fake, "not a video")

      error = assert_raises(RuntimeError) do
        Studio::ReplicateClient::Motion.last_frame(fake, out: File.join(dir, "frame.jpg"))
      end

      assert_match(/could not read the last frame/, error.message)
      refute File.exist?(File.join(dir, "frame.jpg"))
    end
  end
end
