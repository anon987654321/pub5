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
    assert_includes looks.keys, "dilla_heavy"
    assert_includes looks["dmt_bled"].join(" "), "tblend"
    assert_empty looks["none"]
    assert_raises(ArgumentError) { Studio::Promo.look_filters("no_such_look") }
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
end
