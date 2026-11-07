# frozen_string_literal: true

require_relative "minitest_helper"
require "digest"
require "fileutils"
require "json"
require "tmpdir"
require_relative "../photograph/selfie_series"

class TestStudioSelfieSeries < Minitest::Test
  class FakePicture
    @@calls = []

    def self.calls
      @@calls
    end

    def self.reset
      @@calls = []
    end

    def initialize(client:, directory:, subject:, model_manifest:)
      @directory = directory
      @subject = subject
      @model_manifest = model_manifest
    end

    def write(prompt, film:, seed:)
      @@calls << [@subject, File.basename(File.dirname(@model_manifest)), @model_manifest, prompt, film, seed]
      stamp = format("20261107T120000%06d", @@calls.length)
      source = File.join(@directory, "#{stamp}.jpg")
      image = File.join(@directory, "postpro_#{stamp}_test_v1.jpg")
      File.binwrite(source, "source-#{@@calls.length}")
      File.binwrite(image, "graded-#{@@calls.length}")
      sidecar = image + ".json"
      File.write(sidecar, JSON.generate(
        schema: "postpro.grade.v2",
        input: source,
        output: image,
        input_sha256: Digest::SHA256.file(source).hexdigest,
        output_sha256: Digest::SHA256.file(image).hexdigest
      ))
      [source, image, sidecar].each { |file| File.chmod(0o600, file) }
      { "still" => image }
    end
  end

  def setup
    FakePicture.reset
    @root = Dir.mktmpdir("studio-selfie-series-")
    @subjects = File.join(@root, "subjects")
    @output = File.join(@root, "ideas")
    FileUtils.mkdir_p(@subjects, mode: 0o700)
    FileUtils.mkdir_p(@output, mode: 0o700)
    make_subject("johann", %w[daylight night])
    make_subject("merethe", %w[portra])
    @series = Studio::Visual::SelfieSeries.new(
      subjects_directory: @subjects,
      output_directory: @output,
      picture_class: FakePicture,
      clock: -> { Time.utc(2026, 11, 7, 12, 0, 0) }
    )
  end

  def teardown
    FileUtils.remove_entry(@root) if @root && File.directory?(@root)
  end

  def test_generates_ten_distinct_selfies_per_registered_model
    result = @series.write

    assert_equal "complete", result.fetch("status")
    assert_equal 3, result.fetch("models").length
    assert_equal [10, 10, 10], result.fetch("models").map { |model| model.fetch("renders") }
    assert_equal 30, FakePicture.calls.length
    prompts = FakePicture.calls.map { |call| call[3] }
    assert_equal 10, prompts.uniq.length
    assert FakePicture.calls.all? { |call| call[4] == false }
    assert_equal 3, FakePicture.calls.map { |call| call[0] }.uniq.length
    assert_equal (0...10).map { |index| Studio::Visual::SelfieSeries::SEED_BASE + index },
                 FakePicture.calls.first(10).map { |call| call[5] }
  end

  def test_missing_consent_blocks_before_generation_or_retirement
    File.delete(File.join(@subjects, "johann", "consent.yml"))

    assert_raises(ArgumentError) { @series.write }
    assert_empty FakePicture.calls
    refute File.exist?(File.join(@output, ".retired"))
  end

  def test_verified_legacy_family_is_archived_but_unverified_file_is_preserved
    stamp = "20261107T110000123456"
    source = File.join(@output, "#{stamp}.jpg")
    image = File.join(@output, "postpro_#{stamp}_legacy_v1.jpg")
    sidecar = image + ".json"
    File.binwrite(source, "old-source")
    File.binwrite(image, "old-render")
    File.write(sidecar, JSON.generate(
      schema: "postpro.chain.v1",
      input: source,
      output: image,
      input_sha256: Digest::SHA256.file(source).hexdigest,
      output_sha256: Digest::SHA256.file(image).hexdigest
    ))
    [source, image, sidecar].each { |file| File.chmod(0o600, file) }
    orphan = File.join(@output, "20261107T100000123456.jpg")
    File.binwrite(orphan, "unverified")

    result = @series.write

    refute File.exist?(source)
    refute File.exist?(image)
    refute File.exist?(sidecar)
    assert File.file?(orphan)
    assert_equal 3, result.dig("retired", "archived_files")
    assert_equal [File.basename(orphan)], result.dig("retired", "unverified_legacy_files")
  end

  def test_model_manifest_must_be_owner_only
    manifest = File.join(@subjects, "johann", "weights", "daylight", "replicate_training.json")
    File.chmod(0o644, manifest)

    assert_raises(ArgumentError) { @series.write }
    assert_empty FakePicture.calls
  end

  private

  def make_subject(subject, models)
    base = File.join(@subjects, subject)
    weights = File.join(base, "weights")
    FileUtils.mkdir_p(weights, mode: 0o700)

    env = File.join(base, "subject.env")
    File.write(env, "TRIGGER=#{subject.upcase}\nDESCRIPTOR=consistent adult identity\n")
    File.chmod(0o600, env)

    consent = File.join(base, "consent.yml")
    File.write(consent, <<~YAML)
      schema: 1
      subject: #{subject}
      subject_consent:
        likeness_generation: true
        provider_processing: true
      source_rights:
        generation_use: true
        provider_processing: true
        evidence: "verified operator rights record"
    YAML
    File.chmod(0o600, consent)

    models.each do |model|
      path = File.join(weights, model)
      FileUtils.mkdir_p(path, mode: 0o700)
      manifest = File.join(path, "replicate_training.json")
      File.write(manifest, JSON.generate(version: "owner/#{model}:version123"))
      File.chmod(0o600, manifest)
    end
  end
end
