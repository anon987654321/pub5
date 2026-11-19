# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require_relative "minitest_helper"
require_relative "../lora/selfie_film"

class TestSelfieFilm < Minitest::Test
  def setup
    @directory = Dir.mktmpdir("studio-selfie-film-test-")
    @builder = Studio::Lora::SelfieFilm.new(output_root: File.join(@directory, "films"))
  end

  def teardown
    FileUtils.remove_entry(@directory) if @directory && File.directory?(@directory)
  end

  def test_ten_stills_make_a_twenty_five_and_a_half_second_cut
    assert_in_delta 25.5, Studio::Lora::SelfieFilm.expected_duration(10), 0.0001
  end

  def test_single_still_has_no_crossfade_and_keeps_a_valid_duration
    graph = Studio::Lora::SelfieFilm.montage_graph(1)

    refute_includes graph, "xfade="
    assert_includes graph, "zoompan="
    assert_in_delta 3.0, Studio::Lora::SelfieFilm.expected_duration(1), 0.0001
  end

  def test_multi_still_montage_uses_motion_and_overlapping_transitions
    graph = Studio::Lora::SelfieFilm.montage_graph(3)

    assert_equal 2, graph.scan("xfade=transition=fade").length
    assert_includes graph, "duration=0.5:offset=2.5"
    assert_includes graph, "zoompan="
    assert_includes graph, "720x1280"
  end

  def test_audio_filter_normalises_and_fades_the_dilla_bed
    filter = Studio::Lora::SelfieFilm.audio_filter(25.5)

    assert_includes filter, "loudnorm=I=-16:TP=-1.5:LRA=11"
    assert_includes filter, "afade=t=in:st=0:d=0.65"
    assert_includes filter, "afade=t=out:st=23.9:d=1.6"
  end

  def test_audio_filter_refuses_non_finite_or_too_short_durations
    assert_raises(ArgumentError) { Studio::Lora::SelfieFilm.audio_filter(Float::NAN) }
    assert_raises(ArgumentError) { Studio::Lora::SelfieFilm.audio_filter(2.5) }
  end

  def test_media_must_be_private_owned_and_singly_linked
    path = File.join(@directory, "still.jpg")
    File.write(path, "synthetic still")
    File.chmod(0o600, path)

    assert @builder.send(:validate_private_file!, path)

    File.chmod(0o644, path)
    error = assert_raises(Studio::Lora::SelfieFilm::Error) do
      @builder.send(:validate_private_file!, path)
    end
    assert_match(/owner-only/, error.message)
  end

  def test_media_symlinks_are_refused
    source = File.join(@directory, "source.jpg")
    link = File.join(@directory, "linked.jpg")
    File.write(source, "synthetic still")
    File.chmod(0o600, source)
    File.symlink(source, link)

    assert_raises(Studio::Lora::SelfieFilm::Error) do
      @builder.send(:validate_private_file!, link)
    end
  end

  def test_output_path_cannot_be_inside_the_repository
    root = Studio::OutputPaths::REPOSITORY_ROOT
    assert_raises(Studio::Lora::SelfieFilm::Error) do
      Studio::Lora::SelfieFilm.new(output_root: File.join(root, "STUDIO", "output", "test"))
    end
  end

  def test_batch_refuses_empty_subject_list_before_any_provider_call
    report = @builder.run_all(subjects: [], count: 10)

    assert_equal "BLOCKED", report.fetch("state")
    assert_match(/name at least one subject/, report.fetch("reason"))
    refute File.exist?(File.join(@directory, "films"))
  end

  def test_batch_refuses_out_of_range_image_count_before_any_provider_call
    report = @builder.run_all(subjects: ["johann"], count: 13)

    assert_equal "BLOCKED", report.fetch("state")
    assert_match(/between 1 and 12/, report.fetch("reason"))
    refute File.exist?(File.join(@directory, "films"))
  end
end
