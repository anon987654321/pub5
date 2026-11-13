# frozen_string_literal: true

require "fileutils"
require "json"
require "tmpdir"
require_relative "minitest_helper"
require_relative "../lora/selfie_series"

class TestSelfieSeries < Minitest::Test
  # A stand-in for the Replicate predict/download round trip, in the shape
  # idea_picture_test.rb already established for graded stills.
  class FakeClient
    attr_reader :predictions

    def initialize(fail_download_at: nil)
      @predictions = []
      @downloads = []
      @attempts = 0
      @fail_download_at = fail_download_at
    end

    def predict(model_id, input, timeout: nil)
      @predictions << [model_id, input]
      { "output" => "https://replicate.delivery/selfie.jpg" }
    end

    def input_names(_model_id)
      %w[prompt model aspect_ratio num_outputs guidance_scale num_inference_steps output_format output_quality go_fast lora_scale]
    end

    def download_url(url, path)
      @attempts += 1
      raise IOError, "network lost" if @fail_download_at && @attempts == @fail_download_at

      @downloads << path
      File.write(path, "render")
      path
    end
  end

  def setup
    @dir = Dir.mktmpdir
    @client = FakeClient.new
    Studio::Visual::IdeaPicture.class_eval do
      alias_method :grade_without_stub, :grade
      define_method(:grade) { |path, **| path }
      alias_method :still_model_without_stub, :still_model
      define_method(:still_model) { "owner/model:version-123" }
    end
  end

  def teardown
    Studio::Visual::IdeaPicture.class_eval do
      remove_method(:grade)
      alias_method :grade, :grade_without_stub
      remove_method(:grade_without_stub)
      remove_method(:still_model)
      alias_method :still_model, :still_model_without_stub
      remove_method(:still_model_without_stub)
    end
    FileUtils.remove_entry(@dir) if File.directory?(@dir)
  end

  # The graded pass shells out to postpro and the manifest lookup needs a
  # subject with an approved training — both are no-op'd in setup here the way
  # idea_picture_test.rb stubs the same seams, and every write stays in tmpdir.
  def series(fail_download_at: nil)
    Studio::Visual::SelfieSeries.new(
      subject: "probe",
      client: fail_download_at ? FakeClient.new(fail_download_at:) : @client,
      directory: File.join(@dir, "stills"),
      ledger_path: File.join(@dir, "ledger.jsonl"),
    )
  end

  def test_a_series_renders_stills_with_subject_prefixed_filenames_in_the_lora_root
    rendered = run_series(series, count: 3)

    assert_equal 3, rendered.size
    rendered.each { |path| assert File.file?(path) }
    assert File.file?(rendered.first)
    assert rendered.all? { |path| File.basename(path).include?("probe_selfie_") }
  end

  def test_default_output_directory_is_the_lora_root
    box = Studio::Visual::SelfieSeries.new(subject: "probe", client: @client)
    assert_equal Studio::Visual::IdeaPicture::SUBJECTS, box.instance_variable_get(:@directory)
  end

  def test_replace_removes_only_the_selected_subject_series
    directory = File.join(@dir, "flat")
    FileUtils.mkdir_p(directory)
    old = File.join(directory, "probe_selfie_old.jpg")
    processed = File.join(directory, "postpro_probe_selfie_old_v1.jpg")
    other = File.join(directory, "ragnhild_selfie_old.jpg")
    [old, processed, other].each { |path| File.write(path, "old") }

    box = Studio::Visual::SelfieSeries.new(
      subject: "probe", client: @client, directory:, ledger_path: File.join(@dir, "ledger.jsonl"),
    )
    run_series(box, count: 1, replace: true)

    refute File.exist?(old)
    refute File.exist?(processed)
    assert File.exist?(other)
    # A replace deletes the subject's own still and its postpro grade — both
    # match the cleanup patterns — and nothing belonging to another subject.
    assert_equal 2, ledger_rows("replace_cleanup").first.fetch("deleted")
  end

  def test_no_render_carries_the_film_model
    run_series(series, count: 2)

    models = @client.predictions.map(&:first)
    assert_equal 2, models.size
    refute_includes models, Studio::Visual::IdeaPicture::FILM, "a series never renders film"
  end

  def test_count_is_bounded
    error = assert_raises(ArgumentError) { series.run(count: Studio::Visual::SelfieSeries::LIMIT + 1) }
    assert_match(/between 1 and/, error.message)
    refute @client.predictions.any?, "a refused budget makes no paid call"
  end

  def test_a_failed_render_is_recorded_and_the_series_continues
    box = series(fail_download_at: 2)
    rendered = run_series(box, count: 3)

    assert_equal 2, rendered.size, "the network-lost scene is skipped, the series continues"
    attempts = ledger_rows("render_attempt")

    assert attempts.any?, "the failure lands in the ledger, not in silence"
    assert_match(/network lost/, attempts.first["error"])
  end

  def test_renders_are_recorded_in_the_subject_ledger
    run_series(series, count: 2)

    assert_equal 2, ledger_rows("render").size
    row = ledger_rows("render").first

    assert_equal "probe", row["subject"]
    assert row["scene"].to_s.length > 10
  end

  def test_the_scenes_carry_no_intimate_framing
    banned = %w[lingerie nude nudes naked topless shower bathtub underwear intimate bikini]
    text = Studio::Visual::SelfieSeries::SCENES.join("\n").downcase

    assert_empty banned.select { |word| text.include?(word) }
  end

  private

  def run_series(box, **options)
    box.run(**options)
  end

  def ledger_rows(kind)
    path = File.join(@dir, "ledger.jsonl")
    File.file?(path) ? File.readlines(path).map { |line| JSON.parse(line) }.select { |row| row["kind"] == kind } : []
  end
end
