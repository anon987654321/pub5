# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "tmpdir"
require_relative "minitest_helper"
require_relative "../../lora/promo_piece"

class TestPromoPiece < Minitest::Test
  # The piece only orchestrates: still, clips, cut. This stand-in records what
  # it was asked for and never talks to a provider.
  class FakeSeries
    attr_reader :asked, :rendered

    def initialize(still: nil, rendered: [])
      @still = still
      @rendered = rendered
      @asked = nil
    end

    def latest_still = @still

    def run(count:)
      @run_count = count
      @rendered
    end

    attr_reader :run_count

    def film_piece(clips:, seconds:, still:)
      @asked = { clips:, seconds:, still: }
      ["/tmp/clip1.mp4", "/tmp/clip2.mp4"]
    end
  end

  def ffmpeg?
    @ffmpeg ||= Open3.capture2e("ffmpeg", "-version").last.success?
  rescue Errno::ENOENT
    false
  end

  def test_an_existing_still_is_reused_and_the_piece_is_cut_beside_it
    skip "ffmpeg is not on PATH" unless ffmpeg?

    Dir.mktmpdir do |dir|
      still = File.join(dir, "probe_selfie_01.jpg")
      clip = File.join(dir, "clip.mp4")
      audio = File.join(dir, "tone.wav")
      Open3.capture2e("ffmpeg", "-v", "error", "-y", "-f", "lavfi",
                      "-i", "color=c=navy:s=64x64", "-frames:v", "1", still)
      Open3.capture2e("ffmpeg", "-v", "error", "-y", "-f", "lavfi",
                      "-i", "testsrc=size=64x64:rate=30:duration=3", "-pix_fmt", "yuv420p", clip)
      Open3.capture2e("ffmpeg", "-v", "error", "-y", "-f", "lavfi",
                      "-i", "sine=frequency=220:duration=8", audio)

      series = FakeSeries.new(still:)
      series.define_singleton_method(:film_piece) do |clips:, seconds:, still:|
        @asked = { clips:, seconds:, still: }
        [clip, clip]
      end

      out = Studio::Visual::PromoPiece.new(subject: "probe", audio:, series:).run(clips: 2, seconds: 2)

      assert_equal File.join(dir, "probe_promo.mp4"), out
      assert File.file?(out)
      assert_equal({ clips: 2, seconds: 2, still: }, series.asked)
      sidecar = JSON.parse(File.read(File.join(dir, "probe_promo.promo.json")))
      assert_equal 2, sidecar.fetch("clip_count")
      assert_in_delta 3.0, sidecar.fetch("duration_seconds"), 1e-9
    end
  end

  def test_a_subject_without_a_still_renders_one_first
    series = FakeSeries.new(still: nil, rendered: ["/tmp/probe_selfie_01.jpg"])

    error = assert_raises(ArgumentError) do
      Studio::Visual::PromoPiece.new(subject: "probe", audio: "/tmp/none.wav", series:).run
    end

    assert_equal 1, series.run_count
    assert_match(/audio not found/, error.message)
    assert_equal "/tmp/probe_selfie_01.jpg", series.asked.fetch(:still)
  end

  def test_a_subject_with_nothing_to_show_is_refused
    series = FakeSeries.new(still: nil, rendered: [])

    error = assert_raises(RuntimeError) do
      Studio::Visual::PromoPiece.new(subject: "probe", audio: "/tmp/none.wav", series:).run
    end

    assert_match(/no developed still/, error.message)
  end
end
