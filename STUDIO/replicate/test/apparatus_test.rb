# frozen_string_literal: true

require_relative "minitest_helper"
require "tmpdir"
require "fileutils"
require "json"
require "open3"
require_relative "../../lora/apparatus"

# The apparatus pieces are local: ffmpeg and vips, no provider call, so these
# tests run the real operations on a synthetic clip rather than stubbing them.
class TestStudioApparatus < Minitest::Test
  WIDTH = 1080
  HEIGHT = 1920

  def setup
    skip "ffmpeg is not on PATH" unless ffmpeg?
    @dir = Dir.mktmpdir("apparatus")
    @audio = File.join(@dir, "bed.wav")
    @clips = (0...4).map { |i| File.join(@dir, format("probe_film_%02d.mp4", i)) }
    tone(@audio, 8)
    @clips.each { |path| clip(path, 3) }
    @clip = @clips.first
  end

  def teardown
    FileUtils.remove_entry(@dir) if @dir && File.directory?(@dir)
  end

  def test_the_three_pieces_are_written_at_delivery_size_with_provenance
    pieces = Studio::Visual::Apparatus.new(subject: "probe", directory: @dir, audio: @audio,
                                           seconds: 2, shear: 4).run

    assert_equal %w[envelope_cut motion_draw slit_scan], pieces.keys.sort
    pieces.each_value do |path|
      assert File.file?(path), "#{path} must exist"
      assert File.file?("#{path}.json"), "#{path} must carry a sidecar"
      assert_equal [WIDTH, HEIGHT], probe(path, "width,height").map(&:to_i)
    end
    assert_equal 48, probe(pieces["slit_scan"], "nb_frames").first.to_i, "two seconds at 24 fps"
  end

  def test_the_cut_takes_its_lengths_from_the_bed_and_keeps_audio
    pieces = Studio::Visual::Apparatus.new(subject: "probe", directory: @dir, audio: @audio,
                                           seconds: 2, shear: 4).run
    cut = pieces.fetch("envelope_cut")
    record = JSON.parse(File.read("#{cut}.json"))

    assert_operator record.fetch("lengths").length, :<=, 4
    assert_operator record.fetch("lengths").length, :>=, 2
    record.fetch("lengths").each { |length| assert_includes 0.5..2.0, length.round(2) }
    assert audio_stream?(cut), "the cut keeps the bed"
    assert_in_delta record.fetch("lengths").sum, probe(cut, "duration").first.to_f, 0.2
  end

  def test_a_piece_is_never_written_over
    Studio::Visual::Apparatus.new(subject: "probe", directory: @dir, audio: @audio,
                                  seconds: 1, shear: 4).motion_draw(@clip)

    error = assert_raises(RuntimeError) do
      Studio::Visual::Apparatus.new(subject: "probe", directory: @dir, audio: @audio,
                                    seconds: 1, shear: 4).motion_draw(@clip)
    end
    assert_match(/refusing to overwrite/, error.message)
  end

  private

  def ffmpeg?
    _, status = Open3.capture2e("ffmpeg", "-version")
    status.success?
  end

  def tone(path, seconds)
    run_ffmpeg(["-f", "lavfi", "-i", "sine=frequency=220:sample_rate=8000", "-t", seconds.to_s, path])
  end

  def clip(path, seconds)
    run_ffmpeg(["-f", "lavfi", "-i", "testsrc=size=160x284:rate=24", "-t", seconds.to_s,
                "-pix_fmt", "yuv420p", path])
  end

  def run_ffmpeg(args)
    _, status = Open3.capture2e("ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error", "-y", *args)
    raise "ffmpeg failed to build a fixture" unless status.success?
  end

  def audio_stream?(path)
    out, status = Open3.capture2("ffprobe", "-v", "error", "-select_streams", "a",
                                 "-show_entries", "stream=codec_type", "-of", "csv=p=0", path)
    status.success? && out.strip == "audio"
  end

  def probe(path, entries)
    out, status = Open3.capture2("ffprobe", "-v", "error", "-select_streams", "v:0",
                                 "-show_entries", "stream=#{entries}", "-of", "csv=p=0", path)
    raise "ffprobe failed on #{path}" unless status.success?

    out.split("\n").first.to_s.split(",")
  end
end
