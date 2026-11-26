# frozen_string_literal: true

require "fileutils"
require "json"
require "tmpdir"
require "vips"
require_relative "minitest_helper"
require_relative "../chain"
require_relative "../../lora/idea_picture"

Studio::Lora::Consent.define_singleton_method(:require!) { |**| { "valid" => true } }

# A provider stand-in that records what each step asked for and hands back a
# real file, so the chain's feed-forward behaviour is observable.
class ChainClient
  attr_reader :predictions, :uploads

  def initialize(source)
    @source = source
    @predictions = []
    @uploads = []
  end

  def upload_file(path, subject:)
    @uploads << path
    "https://files.example/#{File.basename(path)}?subject=#{subject}"
  end

  def input_names(_model) = %w[prompt image input_image]

  def predict(model, input, timeout: nil)
    @predictions << { "model" => model, "input" => input, "timeout" => timeout }
    { "output" => "https://delivery.example/#{@predictions.length}.jpg" }
  end

  def download_url(_url, path)
    FileUtils.cp(@source, path)
  end
end

class TestStudioReplicateChain < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
    @frame = File.join(@dir, "frame.jpg")
    # A real frame: the local grade runs on whatever the chain hands it.
    Vips::Image.black(64, 96).add(Vips::Image.gaussnoise(64, 96)).cast("uchar").jpegsave(@frame, Q: 90)
    @client = ChainClient.new(@frame)
  end

  def teardown
    FileUtils.remove_entry(@dir) if File.directory?(@dir)
  end

  def test_the_house_chain_runs_repair_then_sharpen_then_stock
    result = Studio::ReplicateClient::Chain.run(
      client: @client, frame: @frame, definition: "stills", subject: "probe", directory: @dir
    )

    assert_equal %w[flux-kontext-apps/restore-image philz1337x/clarity-pro-upscaler levelsio/analog-film],
                 result.fetch("steps").map { |step| step.fetch("model") }
    assert_equal result.fetch("steps").map { |step| step.fetch("model") },
                 @client.predictions.map { |call| call.fetch("model") }
  end

  # native is the escape from three generative passes stacked on a fresh frame.
  # It must hand back the frame it was given and call no model.
  def test_the_native_chain_delivers_the_frame_untouched
    result = Studio::ReplicateClient::Chain.run(
      client: @client, frame: @frame, definition: "native", subject: "probe", directory: @dir
    )

    assert_empty result.fetch("steps")
    assert_empty @client.predictions
    assert_empty @client.uploads
    assert_equal File.binread(@frame), File.binread(result.fetch("path"))
  end

  def test_each_step_hands_its_output_to_the_next
    result = Studio::ReplicateClient::Chain.run(
      client: @client, frame: @frame, definition: "stills", subject: "probe", directory: @dir
    )

    uploaded = @client.uploads.map { |path| File.basename(path) }
    assert_equal File.basename(@frame), uploaded.first
    assert_equal 3, uploaded.length
    # Steps two and three upload what the previous step downloaded.
    refute_equal File.basename(@frame), uploaded[1]
    assert uploaded[1].start_with?("frame_1_restore_image")
    assert uploaded[2].start_with?("frame_1_restore_image_2_clarity_pro_upscaler")
    assert File.file?(result.fetch("path"))
    assert_equal 0o600, File.stat(result.fetch("path")).mode & 0o777
  end

  def test_each_model_receives_the_image_input_it_declares
    Studio::ReplicateClient::Chain.run(
      client: @client, frame: @frame, definition: "stills", subject: "probe", directory: @dir
    )

    keys = @client.predictions.map { |call| call.fetch("input").keys.first }
    assert_equal %w[input_image image image], keys
  end

  def test_provenance_records_the_decision_but_never_the_upload
    steps = Studio::ReplicateClient::Chain.run(
      client: @client, frame: @frame, definition: "stills", subject: "probe", directory: @dir
    ).fetch("steps")

    refute_includes steps.to_s, "files.example"
    assert_equal 2, steps[1].fetch("inputs").fetch("scale_factor")
    assert_includes steps[2].fetch("inputs").fetch("prompt"), "ANLG"
    refute steps[0].fetch("inputs").key?("image")
  end

  def test_an_unknown_chain_is_refused
    error = assert_raises(ArgumentError) do
      Studio::ReplicateClient::Chain.run(
        client: @client, frame: @frame, definition: "no_such_chain", subject: "probe", directory: @dir
      )
    end
    assert_match(/unknown chain/, error.message)
  end

  def test_a_model_outside_the_catalogue_is_refused_before_it_is_called
    steps = [{ "model" => "nobody/not-a-model", "inputs" => {} }]
    error = assert_raises(ArgumentError) do
      Studio::ReplicateClient::Chain.run(
        client: @client, frame: @frame, definition: steps, subject: "probe", directory: @dir
      )
    end

    assert_match(/unknown engine/, error.message)
    assert_empty @client.predictions
  end

  def test_a_failing_step_leaves_the_previous_frame_untouched
    failing = Object.new
    def failing.upload_file(path, subject:) = "https://files.example/#{File.basename(path)}"
    def failing.download_url(_url, path) = FileUtils.cp(@frame, path)
    def failing.predict(_model, _input, timeout: nil) = raise("provider refused")

    assert_raises(RuntimeError) do
      Studio::ReplicateClient::Chain.run(
        client: failing, frame: @frame, definition: "stills", subject: "probe", directory: @dir
      )
    end
    assert_equal 1, Dir.children(@dir).grep(/\.jpg$/).length
    assert_equal ["frame.jpg"], Dir.children(@dir)
  end

  def test_the_budget_is_charged_once_per_step
    charged = 0
    budget = Object.new
    budget.define_singleton_method(:consume!) { charged += 1 }

    Studio::ReplicateClient::Chain.run(
      client: @client, frame: @frame, definition: "stills", subject: "probe", directory: @dir, budget:
    )

    assert_equal 3, charged
  end

  def test_a_developed_still_carries_the_chain_in_its_receipt
    picture = Studio::Visual::IdeaPicture.new(
      subject: "probe", client: @client, directory: @dir, engine: "black-forest-labs/flux-dev"
    )
    result = picture.write(
      "a quiet portrait against a north window", film: false, output_stem: "probe_selfie_01",
      preset: "house", chain: Studio::Lora::Craft::STILL_CHAIN, discard_raw: true
    )

    receipt = JSON.parse(File.read("#{result.fetch("capture").fetch("original")}.json"))
    assert_equal 3, receipt.fetch("chain").length
    assert_equal "levelsio/analog-film", receipt.fetch("chain").last.fetch("model")
    # The raw prediction and every intermediate the chain made are gone; only
    # the developed frame and its receipts remain.
    assert_equal 1, (Dir.children(@dir).grep(/\.jpg$/) - ["frame.jpg"]).length
  end

  def test_every_chain_step_names_a_model_the_catalogue_knows_with_an_image_input
    Studio::ReplicateClient::Chain.definitions.each_key do |name|
      Studio::ReplicateClient::Chain.definition(name).each do |step|
        inputs = Studio::ReplicateClient::Models.any_inputs_for(step.fetch("model"))
        assert Studio::ReplicateClient::Chain::IMAGE_INPUTS.any? { |key| inputs.include?(key) },
               "#{name}: #{step.fetch("model")} declares no image input"
      end
    end
  end

  def test_the_fallback_chain_names_only_models_the_catalogue_carries
    Studio::ReplicateClient::Models.chain_for(Studio::ReplicateClient::Models.default_engine).each do |name|
      next if name == "$subject_lora"

      assert Studio::ReplicateClient::Models.any_engine(name), "#{name} is not in the catalogue"
    end
  end

  # A step that names an input its model does not take fails at the API, after
  # the frame has already been rendered and uploaded. Catch it offline.
  def test_every_declared_step_input_exists_on_its_model
    Studio::ReplicateClient::Chain.definitions.each_key do |name|
      Studio::ReplicateClient::Chain.definition(name).each do |step|
        model = step.fetch("model")
        declared = Studio::ReplicateClient::Models.any_inputs_for(model)
        (step["inputs"] || {}).each_key do |key|
          assert_includes declared, key.to_s, "#{name}: #{model} has no #{key} input"
        end
      end
    end
  end
end
