# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require_relative "minitest_helper"
require_relative "../lora/idea_picture"
require_relative "../lora/selfie_series"
require_relative "../lora/selfies_gallery"
require_relative "../replicate/client"

class TestStudioConsentEnforcement < Minitest::Test
  class ProviderSpy
    attr_reader :calls

    def initialize
      @calls = []
    end

    def input_names(*)
      @calls << :input_names
      []
    end

    def predict(*)
      @calls << :predict
      raise "provider prediction must not start"
    end

    def upload_file(*)
      @calls << :upload_file
      raise "provider upload must not start"
    end

    def download_url(*)
      @calls << :download_url
      raise "provider download must not start"
    end
  end

  def setup
    @root = Dir.mktmpdir("studio-consent-boundary-")
    @provider = ProviderSpy.new
  end

  def teardown
    FileUtils.remove_entry(@root) if File.directory?(@root)
  end

  def subject_directory(root)
    directory = File.join(root, "probe")
    FileUtils.mkdir_p(directory, mode: 0o700)
    directory
  end

  def test_still_render_requires_consent_before_provider_schema_or_prediction
    directory = subject_directory(File.join(@root, "subjects"))
    picture = Studio::Visual::IdeaPicture.new(
      subject: "probe", client: @provider, directory: @root
    )
    picture.instance_variable_set(:@subject_directory, directory)

    error = assert_raises(Studio::Lora::Consent::Error) do
      picture.write("portrait", film: false)
    end

    assert_match(/private consent.yml is missing/, error.message)
    assert_empty @provider.calls
    assert_empty Dir.children(@root).grep(/\.jpg\z/)
  end

  def test_selfie_series_requires_consent_before_preflight_and_replace_cleanup
    lora_root = File.join(@root, "lora")
    directory = subject_directory(lora_root)
    previous = File.join(lora_root, "probe_selfie_01.jpg")
    File.write(previous, "keep this render")
    series = Studio::Visual::SelfieSeries.new(
      subject: "probe", client: @provider, directory: lora_root,
      ledger_path: File.join(@root, "ledger.jsonl")
    )
    series.instance_variable_get(:@series).instance_variable_set(:@subject_directory, directory)

    error = assert_raises(Studio::Lora::Consent::Error) do
      series.run(count: 1, replace: true)
    end

    assert_match(/private consent.yml is missing/, error.message)
    assert_empty @provider.calls
    assert_equal "keep this render", File.read(previous)
    refute File.exist?(File.join(@root, "ledger.jsonl"))
  end

  def test_gallery_requires_separate_publication_permission_before_manifest_write
    lora_root = File.join(@root, "lora")
    subject_directory(lora_root)
    File.write(File.join(lora_root, "probe_selfie_01.jpg"), "local render")
    manifest = File.join(@root, "manifest.js")
    gallery = Studio::Visual::SelfiesGallery.new(
      root: lora_root, consent_root: lora_root, out: manifest
    )

    error = assert_raises(Studio::Lora::Consent::Error) { gallery.build }

    assert_match(/private consent.yml is missing/, error.message)
    refute File.exist?(manifest)
  end

  def test_training_is_refused_before_any_provider_request
    subject = "consent_probe_#{Process.pid}_#{Time.now.to_i}"
    client_class = Class.new(Studio::ReplicateClient) do
      attr_reader :requests

      def initialize
        @requests = []
        super(token: "unused-test-token")
      end

      def get(*)
        @requests << :get
        raise "provider GET must not start"
      end

      def post(*)
        @requests << :post
        raise "provider POST must not start"
      end
    end
    client = client_class.new

    error = assert_raises(Studio::Lora::Consent::Error) do
      client.train_lora(
        "https://files.replicate.delivery/photos.zip",
        "owner/model", subject:, wait: false
      )
    end

    assert_match(/subject directory is missing or is a symlink|private consent.yml is missing/, error.message)
    assert_empty client.requests
  end
end
