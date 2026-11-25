# frozen_string_literal: true

require_relative "minitest_helper"
require_relative "../promo"
require "tmpdir"
require "open3"

class TestPromo < Minitest::Test
  def stills(count)
    (1..count).map { |n| "/tmp/still#{n}.jpg" }
  end

  # The crossfade offset is the one number that silently truncates the piece:
  # a wrong offset drops whole stills and the clip ends early. Pin the exact
  # values for a known still length.
  def test_crossfade_offsets_advance_by_the_step_not_the_full_still
    assert_equal [3.5, 7.0, 10.5],
                 Studio::Promo.crossfade_offsets(4, 4.5, 1.0)
    assert_equal [], Studio::Promo.crossfade_offsets(1, 4.5, 1.0)
  end

  def test_total_seconds_subtracts_each_overlap
    assert_in_delta 15.0, Studio::Promo.total_seconds(4, still_seconds: 4.5, crossfade: 1.0), 1e-9
    assert_in_delta 4.5, Studio::Promo.total_seconds(1, still_seconds: 4.5, crossfade: 1.0), 1e-9
    assert_in_delta 0.0, Studio::Promo.total_seconds(0), 1e-9
  end

  def test_build_args_loops_each_still_and_crossfades_them
    args = Studio::Promo.build_args(stills: stills(3), audio: "dilla.wav", out: "out.mp4",
                                    look: "none", still_seconds: 4.5, crossfade: 1.0)

    assert_equal 3, args.count { |token| token == "-loop" }, "each still is a looped input"
    assert_equal 3, args.count { |token| token == "-framerate" }
    graph = args[args.index("-filter_complex") + 1]
    assert_equal 2, graph.scan(/xfade=/).length, "n stills need n-1 crossfades"
    assert_includes graph, "offset=3.5"
    assert_includes graph, "offset=7"
    assert_includes graph, "loudnorm=I=-14"
    assert_equal "out.mp4", args.last
  end

  def test_the_look_is_read_from_video_yml
    looks = Studio::Promo.looks
    assert_same Studio::Promo::LOOKS, looks, "the compatibility constant must alias the canonical catalogue"
    assert_includes looks.keys, "dilla_heavy"
    assert_includes looks["dmt_bled"].join(" "), "tblend"
    assert_empty looks["none"]
    assert_raises(ArgumentError) { Studio::Promo.look_filters("no_such_look") }
  end

  def test_video_catalogue_rejects_an_unknown_schema_and_non_string_filters
    error = assert_raises(ArgumentError) do
      Studio::Promo.parse_video_presets("schema: other\npresets: {}\n")
    end
    assert_match(/unsupported video grade schema/, error.message)

    error = assert_raises(ArgumentError) do
      Studio::Promo.parse_video_presets(<<~YAML)
        schema: postpro.video.v1
        presets:
          broken:
            filters: nope
      YAML
    end
    assert_match(/needs a list of non-empty filter strings/, error.message)
  end

  def test_look_filters_reach_the_graph
    heavy = Studio::Promo.build_args(stills: stills(1), audio: "a.wav", out: "o.mp4", look: "dilla_heavy")
    plain = Studio::Promo.build_args(stills: stills(1), audio: "a.wav", out: "o.mp4", look: "none")
    heavy_graph = heavy[heavy.index("-filter_complex") + 1]
    plain_graph = plain[plain.index("-filter_complex") + 1]

    assert_includes heavy_graph, "vignette=PI/5"
    refute_includes plain_graph, "vignette"
  end

  def test_stills_for_subject_reads_only_that_subjects_stills
    Dir.mktmpdir do |root|
      directory = File.join(root, "merethe")
      FileUtils.mkdir_p(directory)
      File.write(File.join(directory, "merethe_selfie_01.jpg"), "x")
      File.write(File.join(directory, "merethe_selfie_02.png"), "x")
      File.write(File.join(directory, "merethe_selfie_02.txt"), "caption")
      File.write(File.join(directory, "johann_selfie_01.jpg"), "x")

      found = Studio::Promo.stills_for_subject("merethe", root: root)
      assert_equal %w[merethe_selfie_01.jpg merethe_selfie_02.png],
                   found.map { |path| File.basename(path) }
    end
  end

  def test_plan_api_reports_the_cut_before_any_render
    Dir.mktmpdir do |root|
      directory = File.join(root, "merethe")
      FileUtils.mkdir_p(directory)
      File.write(File.join(directory, "merethe_selfie_01.jpg"), "x")

      out = StringIO.new
      status = Studio::Api.respond(
        Studio::Promo::CLI.api_actions, argv: ["api", '{"action":"plan","subject":"merethe"}'],
        output: out
      )
      assert_equal 0, status
      # plan reads the real STUDIO/lora tree, so just prove the shape is sound.
      result = JSON.parse(out.string).fetch("result")
      assert_equal "dilla_heavy", result["look"]
      assert_includes result["looks"], "dmt_bled"
    end
  end

  def test_render_writes_a_playable_clip_with_real_audio
    skip "ffmpeg is not on PATH" unless Studio::Promo.ffmpeg?

    Dir.mktmpdir do |dir|
      still = File.join(dir, "still.png")
      audio = File.join(dir, "tone.wav")
      out = File.join(dir, "cut.mp4")
      Open3.capture2e("ffmpeg", "-v", "error", "-y", "-f", "lavfi",
                      "-i", "color=c=navy:s=64x64", "-frames:v", "1", still)
      Open3.capture2e("ffmpeg", "-v", "error", "-y", "-f", "lavfi",
                      "-i", "sine=frequency=220:duration=6", audio)

      Studio::Promo.render(stills: [still, still], audio:, out:, look: "none",
                           size: [64, 112], still_seconds: 2.0, crossfade: 0.5)

      probe, = Open3.capture2e("ffprobe", "-v", "error", "-show_entries",
                               "stream=codec_type", "-of", "csv=p=0", out)
      assert_includes probe, "video"
      assert_includes probe, "audio"
      duration, = Open3.capture2e("ffprobe", "-v", "error", "-show_entries",
                                  "format=duration", "-of", "csv=p=0", out)
      assert_in_delta 3.5, duration.to_f, 0.35
      assert File.file?(File.join(dir, "cut.promo.json")), "a render writes its sidecar"
    end
  end

  def clips(count)
    (1..count).map { |n| "/tmp/clip#{n}.mp4" }
  end

  def test_build_args_trims_clips_instead_of_looping_them
    args = Studio::Promo.build_args(clips: clips(3), audio: "dilla.wav", out: "out.mp4",
                                    look: "none", clip_seconds: 12.0, crossfade: 1.0)
    graph = args[args.index("-filter_complex") + 1]

    refute_includes args.join(" "), "-loop"
    assert_includes graph, "[0:v]trim=duration=12,setpts=PTS-STARTPTS"
    assert_includes graph, "xfade=transition=fade:duration=1:offset=11"
    assert_includes graph, "xfade=transition=fade:duration=1:offset=22"
  end

  def test_clips_lead_and_stills_fill_the_piece
    args = Studio::Promo.build_args(clips: clips(1), stills: stills(2), audio: "a.wav",
                                    out: "o.mp4", look: "none", clip_seconds: 12.0,
                                    still_seconds: 4.5, crossfade: 1.0)
    graph = args[args.index("-filter_complex") + 1]

    assert_includes graph, "[0:v]trim=duration=12"
    assert_includes args.join(" "), "-loop 1"
    # Three picture inputs and the track: the audio is index three.
    assert_includes graph, "[3:a]loudnorm"
  end

  def test_piece_seconds_counts_each_segment_and_each_overlap
    clips_only = Studio::Promo.segments_for(clips: clips(3), clip_seconds: 12.0)
    assert_in_delta 34.0, Studio::Promo.piece_seconds(clips_only, crossfade: 1.0), 1e-9

    mixed = Studio::Promo.segments_for(clips: clips(2), stills: stills(2),
                                       clip_seconds: 12.0, still_seconds: 4.5)
    # 24 seconds of clip and 9 of still, less three one-second overlaps.
    assert_in_delta 30.0, Studio::Promo.piece_seconds(mixed, crossfade: 1.0), 1e-9
  end

  def test_crossfade_offsets_read_mixed_segment_lengths
    segments = Studio::Promo.segments_for(clips: clips(1), stills: stills(2),
                                          clip_seconds: 12.0, still_seconds: 4.5)

    assert_equal [11.0, 14.5], Studio::Promo.crossfade_offsets(segments, 1.0)
  end

  def test_render_refuses_a_missing_segment
    Dir.mktmpdir do |dir|
      audio = File.join(dir, "tone.wav")
      File.write(audio, "not really audio")

      error = assert_raises(ArgumentError) do
        Studio::Promo.render(clips: [File.join(dir, "gone.mp4")], audio:,
                             out: File.join(dir, "cut.mp4"), look: "none")
      end

      assert_match(/segment not found/, error.message)
    end
  end

  def test_a_subject_with_clips_cuts_from_the_clips_and_ignores_the_stills
    Dir.mktmpdir do |dir|
      subject = File.join(dir, "probe")
      FileUtils.mkdir_p(subject)
      File.write(File.join(subject, "probe_film_01.mp4"), "clip")
      File.write(File.join(subject, "probe_selfie_01.jpg"), "still")

      segments = Studio::Promo.segments_for_subject("probe", root: dir)

      assert_equal ["clip"], segments.map { |segment| segment.fetch(:kind) }
      assert_equal File.join(subject, "probe_film_01.mp4"), segments.first.fetch(:path)
      assert_in_delta 12.0, segments.first.fetch(:seconds), 1e-9
    end
  end

  def test_a_subject_without_clips_falls_back_to_stills
    Dir.mktmpdir do |dir|
      subject = File.join(dir, "probe")
      FileUtils.mkdir_p(subject)
      File.write(File.join(subject, "probe_selfie_01.jpg"), "still")

      segments = Studio::Promo.segments_for_subject("probe", root: dir)

      assert_equal ["still"], segments.map { |segment| segment.fetch(:kind) }
      assert_in_delta 4.5, segments.first.fetch(:seconds), 1e-9
    end
  end

  def test_render_cuts_clips_into_a_playable_piece_and_records_them
    skip "ffmpeg is not on PATH" unless Studio::Promo.ffmpeg?

    Dir.mktmpdir do |dir|
      clip = File.join(dir, "clip.mp4")
      audio = File.join(dir, "tone.wav")
      out = File.join(dir, "cut.mp4")
      Open3.capture2e("ffmpeg", "-v", "error", "-y", "-f", "lavfi",
                      "-i", "testsrc=size=64x64:rate=30:duration=3", "-pix_fmt", "yuv420p", clip)
      Open3.capture2e("ffmpeg", "-v", "error", "-y", "-f", "lavfi",
                      "-i", "sine=frequency=220:duration=8", audio)

      Studio::Promo.render(clips: [clip, clip], audio:, out:, look: "none",
                           size: [64, 112], clip_seconds: 2.0, crossfade: 0.5)

      duration, = Open3.capture2e("ffprobe", "-v", "error", "-show_entries",
                                  "format=duration", "-of", "csv=p=0", out)
      assert_in_delta 3.5, duration.to_f, 0.4

      sidecar = JSON.parse(File.read(File.join(dir, "cut.promo.json")))
      assert_equal 2, sidecar.fetch("clip_count")
      assert_equal 0, sidecar.fetch("still_count")
      assert_equal %w[clip clip], sidecar.fetch("segments").map { |segment| segment.fetch("kind") }
      assert_in_delta 3.5, sidecar.fetch("duration_seconds"), 1e-9
    end
  end
end
