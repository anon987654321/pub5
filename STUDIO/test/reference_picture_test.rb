# frozen_string_literal: true

require_relative "minitest_helper"
require "fileutils"
require "json"
require "tmpdir"
require_relative "../photograph/reference_picture"

class TestStudioReferencePicture < Minitest::Test
  class StubClient
    attr_reader :uploads, :runs, :downloads

    def initialize
      @uploads = []
      @runs = []
      @downloads = []
    end

    def upload_file(path)
      @uploads << path
      "https://files.replicate.delivery/reference-#{@uploads.length}.jpg"
    end

    def run(model, input, timeout:)
      @runs << [model, input, timeout]
      {
        "id" => "prediction_123",
        "version" => "version_123",
        "output" => ["https://replicate.delivery/output.webp"]
      }
    end

    def download_url(url, path)
      @downloads << [url, path]
      File.binwrite(path, "rendered-webp")
      path
    end
  end

  def setup
    @root = Dir.mktmpdir("studio-reference-test-")
    @sources = File.join(@root, "merethe", "sources")
    @output = File.join(@root, "output")
    FileUtils.mkdir_p(@sources, mode: 0o700)
    @consent = File.join(@root, "merethe", "consent.yml")
    File.write(@consent, consent_yaml)
    File.chmod(0o600, @consent)
    @client = StubClient.new
    @picture = Studio::Visual::ReferencePicture.new(
      subject: "merethe",
      client: @client,
      source_directory: @sources,
      consent_path: @consent,
      output_directory: @output
    )
    @front = image("front.png", "front-image")
    @three_quarter = image("three-quarter.png", "three-quarter-image")
    @expression = image("expression.png", "expression-image")
  end

  def teardown
    FileUtils.remove_entry(@root) if @root && File.directory?(@root)
  end

  def test_preflight_is_local_only_and_returns_a_reproducible_plan
    plan = @picture.preflight(
      prompt: "A relaxed daylight selfie outdoors.",
      references: [@front, @three_quarter, @expression],
      cost_limit_usd: 0.03
    )

    assert_equal "ready", plan.fetch(:state)
    assert_equal "qwen/qwen-image-edit-2511", plan.fetch(:model)
    assert_equal %w[front three_quarter expression], plan.fetch(:reference_roles)
    assert_includes plan.fetch(:rendered_prompt), "natural selfie"
    assert_empty @client.uploads
    assert_empty @client.runs
  end

  def test_write_uploads_only_after_preflight_and_writes_private_receipt
    result = @picture.write(
      prompt: "A relaxed daylight selfie outdoors.",
      references: [@front, @three_quarter, @expression],
      cost_limit_usd: 0.03
    )

    assert_equal "complete", result.fetch("status")
    assert_equal 3, @client.uploads.length
    model, input, timeout = @client.runs.fetch(0)
    assert_equal "qwen/qwen-image-edit-2511", model
    assert_equal 3, input.fetch(:image).length
    assert_equal 42, input.fetch(:seed)
    assert_equal "match_input_image", input.fetch(:aspect_ratio)
    assert_equal 600, timeout
    assert File.file?(result.fetch("image"))
    assert File.file?(result.fetch("receipt"))
    assert_equal 0o600, File.stat(result.fetch("image")).mode & 0o777
    assert_equal 0o600, File.stat(result.fetch("receipt")).mode & 0o777
    receipt = JSON.parse(File.read(result.fetch("receipt")))
    assert_equal "version_123", receipt.fetch("model_version")
    assert_equal 3, receipt.fetch("reference_sha256").length
    refute receipt.to_json.include?("replicate.delivery")
  end

  def test_missing_consent_blocks_before_any_upload
    File.delete(@consent)

    error = assert_raises(ArgumentError) do
      @picture.write(prompt: "A portrait", references: [@front], cost_limit_usd: 0.03)
    end

    assert_match(/missing private consent record/, error.message)
    assert_empty @client.uploads
    assert_empty @client.runs
  end

  def test_source_rights_must_be_explicit_even_when_person_consent_exists
    File.write(@consent, consent_yaml.sub("generation_use: true", "generation_use: false"))
    File.chmod(0o600, @consent)

    error = assert_raises(ArgumentError) do
      @picture.preflight(prompt: "A portrait", references: [@front], cost_limit_usd: 0.03)
    end

    assert_match(/source-image rights/, error.message)
  end

  def test_underfunded_cost_limit_blocks_before_upload
    error = assert_raises(ArgumentError) do
      @picture.write(prompt: "A portrait", references: [@front], cost_limit_usd: 0.02)
    end

    assert_match(/cost limit/, error.message)
    assert_empty @client.uploads
  end

  def test_duplicate_images_are_rejected
    error = assert_raises(ArgumentError) do
      @picture.preflight(prompt: "A portrait", references: [@front, @front], cost_limit_usd: 0.03)
    end

    assert_match(/duplicate reference/, error.message)
  end

  def test_reference_outside_sources_is_rejected
    outside = File.join(@root, "outside.png")
    File.binwrite(outside, png_header)

    error = assert_raises(ArgumentError) do
      @picture.preflight(prompt: "A portrait", references: [outside], cost_limit_usd: 0.03)
    end

    assert_match(/escapes the subject sources/, error.message)
  end

  def test_symlink_reference_is_rejected
    link = File.join(@sources, "linked.png")
    File.symlink(@front, link)

    error = assert_raises(ArgumentError) do
      @picture.preflight(prompt: "A portrait", references: [link], cost_limit_usd: 0.03)
    end

    assert_match(/non-symlink/, error.message)
  end

  def test_invalid_image_signature_is_rejected
    invalid = File.join(@sources, "not-really.png")
    File.binwrite(invalid, "not an image")

    error = assert_raises(ArgumentError) do
      @picture.preflight(prompt: "A portrait", references: [invalid], cost_limit_usd: 0.03)
    end

    assert_match(/signature/, error.message)
  end

  def test_more_than_three_references_is_rejected
    error = assert_raises(ArgumentError) do
      @picture.preflight(
        prompt: "A portrait",
        references: [@front, @three_quarter, @expression, @front + ".copy"],
        cost_limit_usd: 0.03
      )
    end

    assert_match(/1..3/, error.message)
  end

  def test_subject_path_traversal_is_rejected
    assert_raises(ArgumentError) do
      Studio::Visual::ReferencePicture.new(subject: "../elsewhere")
    end
  end

  def test_output_inside_checkout_is_rejected_before_upload
    picture = Studio::Visual::ReferencePicture.new(
      subject: "merethe",
      client: @client,
      source_directory: @sources,
      consent_path: @consent,
      output_directory: File.expand_path("../../..", __dir__)
    )

    assert_raises(ArgumentError) do
      picture.write(prompt: "A portrait", references: [@front], cost_limit_usd: 0.03)
    end
    assert_empty @client.uploads
  end

  private

  def image(name, contents)
    path = File.join(@sources, name)
    File.binwrite(path, png_header + contents)
    path
  end

  def png_header
    "\x89PNG\r\n\x1A\n".b + [13].pack("N") + "IHDR" + [640, 480].pack("NN") + "\x08\x02\x00\x00\x00".b
  end

  def consent_yaml
    <<~YAML
      schema: 1
      subject: merethe
      subject_consent:
        likeness_generation: true
        provider_processing: true
      source_rights:
        generation_use: true
        provider_processing: true
        evidence: "operator-confirmed image rights record"
    YAML
  end
end
