# frozen_string_literal: true

require "json"
require "minitest/autorun"
require "minitest/mock"
require_relative "../../studio/replicate/lora/merethe/prepare"

class MeretheLoraTest < Minitest::Test
  Subject = Studio::MeretheLora

  FakeReply = Struct.new(:status, :body)
  FakeRun = Struct.new(:out, :err, :successful) do
    def ok? = successful
  end

  class FakeWorld
    Manifest = Struct.new(:root)
    attr_reader :manifest, :writes, :net_calls, :exec_calls

    def initialize(files = {})
      @files = files
      @manifest = Manifest.new("/tmp/pub5")
      @writes = {}
      @net_calls = []
      @exec_calls = []
    end

    def read(path)
      @files.fetch(path) { raise Errno::ENOENT, path }
    end

    def write(path, content, mode: nil)
      @writes[path] = { content:, mode: }
      path
    end

    def net(method, url)
      @net_calls << [method, url]
      FakeReply.new(404, "")
    end

    def exec(*argv, chdir:, **_options)
      @exec_calls << [argv, chdir]
      FakeRun.new("", "", true)
    end
  end

  def test_archive_inventory_is_complete_and_pinned
    assert_equal 15, Subject::SOURCE_FILES.size
    assert_equal "8e1955ae130592ab7c20ee266c024f061431c67e", Subject::SOURCE_COMMIT
    assert Subject::SOURCE_FILES.values.all? { |sha| sha.match?(/\A[0-9a-f]{40}\z/) }
  end

  def test_only_face_led_non_intimate_archive_frames_are_selected
    assert_equal %w[10.jpg 11.jpg 12.jpg 13.jpg], Subject::CURATED_CAPTIONS.keys
    assert Subject::CURATED_CAPTIONS.values.all? { |caption| caption.include?("MERETHE") }
  end

  def test_git_blob_sha_matches_git_object_format
    assert_equal "b6fc4c620b67d95f953a5c1c1230aaab5db5a1b0", Subject.git_blob_sha("hello")
  end

  def test_preparation_blocks_until_originals_are_recovered
    world = FakeWorld.new

    report = Subject.prepare!(world:)

    assert_equal "BLOCKED_MISSING_RECOVERED_SOURCES", report.fetch("status")
    assert_equal 4, report.fetch("missing_selected_sources").size
    refute report.fetch("training_started")
    refute report.fetch("provider_upload_started")
    assert_empty world.exec_calls
  end

  def test_additional_photos_require_valid_signatures_and_trigger_captions
    filename = "portrait.jpg"
    bytes = "\xFF\xD8\xFF\xD9".b
    manifest = [{ "file" => filename, "caption" => "MERETHE, a portrait in daylight." }]
    world = FakeWorld.new(
      Subject::ADDITIONAL_MANIFEST => JSON.generate(manifest),
      "#{Subject::ADDITIONAL_ROOT}/#{filename}" => bytes
    )

    images, problems = Subject.additional_images(world:)

    assert_empty problems
    assert_equal [filename], images.map { |image| image[:file] }
  end

  def test_additional_photo_path_traversal_is_rejected
    manifest = [{ "file" => "../private.jpg", "caption" => "MERETHE portrait" }]
    world = FakeWorld.new(Subject::ADDITIONAL_MANIFEST => JSON.generate(manifest))

    images, problems = Subject.additional_images(world:)

    assert_empty images
    assert_includes problems.join("\n"), "invalid additional image filename"
  end

  def test_ready_dataset_is_written_and_zipped_through_core_world
    bytes = "\xFF\xD8\xFF\xD9".b
    files = Subject::CURATED_CAPTIONS.keys.to_h do |name|
      ["#{Subject::SOURCE_ROOT}/#{name}", bytes]
    end
    extra_records = 6.times.map do |index|
      filename = "extra-#{index + 1}.jpg"
      files["#{Subject::ADDITIONAL_ROOT}/#{filename}"] = bytes
      { "file" => filename, "caption" => "MERETHE, everyday portrait #{index + 1}." }
    end
    files[Subject::ADDITIONAL_MANIFEST] = JSON.generate(extra_records)
    world = FakeWorld.new(files)

    report = Subject.stub(:verified_original?, true) do
      Subject.prepare!(world:)
    end

    assert_equal "READY_FOR_OPERATOR_REVIEW", report.fetch("status")
    assert_equal 10, report.fetch("candidate_count")
    assert_equal "zip", world.exec_calls.fetch(0).first.fetch(0)
    assert world.writes.keys.any? { |path| path.start_with?(Subject::DATASET_ROOT) }
    refute report.fetch("training_started")
    refute report.fetch("provider_upload_started")
  end
end
